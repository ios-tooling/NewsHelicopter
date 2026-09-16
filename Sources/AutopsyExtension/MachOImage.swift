//
//  MachOImage.swift
//  AutopsyExtension
//
//  A Mach-O image as it sits in another task: its header and load commands
//  read through the task's memory, so a section can be found by name without
//  the image's symbols (which a shipping build does not have) and without
//  trusting anything in this process to be laid out the same way.
//

import Darwin
import Foundation
import MachO

public struct MachOImage: Sendable {
	public struct Section: Sendable, Equatable {
		public let segment: String
		public let name: String
		/// Where the section is in the task — slid, ready to read.
		public let address: UInt64
		public let size: UInt64
	}

	public let memory: TaskMemory
	public let baseAddress: UInt64
	public let fileType: UInt32
	private let commands: Data
	/// The difference between where the image was linked to load and where it did.
	public let slide: Int64

	/// Nil unless a 64-bit Mach-O header is readable at `baseAddress`.
	public init?(memory: TaskMemory, baseAddress: UInt64) {
		guard let header = memory.read(baseAddress, count: MemoryLayout<mach_header_64>.size),
		      header.load(UInt32.self, at: 0) == MH_MAGIC_64 else { return nil }
		let commandCount = Int(header.load(UInt32.self, at: 16))
		let commandBytes = Int(header.load(UInt32.self, at: 20))
		guard commandCount > 0, commandBytes > 0, commandBytes < 1 << 20,
		      let commands = memory.read(baseAddress + UInt64(MemoryLayout<mach_header_64>.size), count: commandBytes) else { return nil }
		self.memory = memory
		self.baseAddress = baseAddress
		self.fileType = header.load(UInt32.self, at: 12)
		self.commands = commands
		var textAddress: UInt64?
		Self.forEachCommand(in: commands, count: commandCount) { command, offset in
			guard command == UInt32(LC_SEGMENT_64), textAddress == nil, commands.machOName(at: offset + 8) == "__TEXT" else { return }
			textAddress = commands.load(UInt64.self, at: offset + 24)
		}
		self.slide = Int64(bitPattern: baseAddress &- (textAddress ?? baseAddress))
	}

	public var isExecutable: Bool { fileType == UInt32(MH_EXECUTE) }

	public var uuid: UUID? {
		var found: UUID?
		Self.forEachCommand(in: commands, count: Int.max) { command, offset in
			guard command == UInt32(LC_UUID), found == nil, offset + 24 <= commands.count else { return }
			var bytes = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
			withUnsafeMutableBytes(of: &bytes) { $0.copyBytes(from: commands[(commands.startIndex + offset + 8)..<(commands.startIndex + offset + 24)]) }
			found = UUID(uuid: bytes)
		}
		return found
	}

	public struct Segment: Sendable, Equatable {
		public let name: String
		public let address: UInt64
		public let size: UInt64
	}

	/// Every segment, slid, in load-command order.
	public var segments: [Segment] {
		var segments: [Segment] = []
		Self.forEachCommand(in: commands, count: Int.max) { command, offset in
			guard command == UInt32(LC_SEGMENT_64) else { return }
			let address = commands.load(UInt64.self, at: offset + 24)
			segments.append(Segment(name: commands.machOName(at: offset + 8),
			                        address: UInt64(bitPattern: Int64(bitPattern: address) &+ slide),
			                        size: commands.load(UInt64.self, at: offset + 32)))
		}
		return segments
	}

	/// Every section, in load-command order.
	public var sections: [Section] {
		var sections: [Section] = []
		Self.forEachCommand(in: commands, count: Int.max) { command, offset in
			guard command == UInt32(LC_SEGMENT_64) else { return }
			let segment = commands.machOName(at: offset + 8)
			let count = Int(commands.load(UInt32.self, at: offset + 64))
			let sectionSize = MemoryLayout<section_64>.size
			for index in 0..<count {
				let at = offset + MemoryLayout<segment_command_64>.size + index * sectionSize
				guard at + sectionSize <= commands.count else { return }
				let address = commands.load(UInt64.self, at: at + 32)
				sections.append(Section(segment: segment, name: commands.machOName(at: at),
				                        address: UInt64(bitPattern: Int64(bitPattern: address) &+ slide),
				                        size: commands.load(UInt64.self, at: at + 40)))
			}
		}
		return sections
	}

	/// The first section called `name`; in `segment` when given, else in any.
	public func section(_ name: String, in segment: String? = nil) -> Section? {
		sections.first { $0.name == name && (segment == nil || $0.segment == segment) }
	}

	/// A section's bytes.
	public func contents(of section: Section) -> Data? {
		guard section.size > 0, section.size < 1 << 24 else { return nil }
		return memory.read(section.address, count: Int(section.size))
	}

	private static func forEachCommand(in commands: Data, count: Int, _ body: (_ command: UInt32, _ offset: Int) -> Void) {
		var offset = 0, seen = 0
		while offset + 8 <= commands.count, seen < count {
			let command = commands.load(UInt32.self, at: offset)
			let size = Int(commands.load(UInt32.self, at: offset + 4))
			guard size >= 8, offset + size <= commands.count else { return }
			body(command, offset)
			offset += size
			seen += 1
		}
	}
}
