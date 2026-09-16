//
//  TaskMemory.swift
//  NewsHelicopterExtension
//
//  Reads another task's memory through its port: the corpse's in the
//  extension, the current task's in a test — the kernel does not care which.
//  Every read is bounded and can fail; the callers are all prepared for a
//  pointer that leads nowhere, because in a crashed process some do.
//

import Darwin
import Foundation

public struct TaskMemory: Sendable {
	public let task: mach_port_t

	public init(task: mach_port_t) {
		self.task = task
	}

	/// The current task, for reading one's own images and threads.
	public static var current: TaskMemory { TaskMemory(task: mach_task_self_) }

	public func read(_ address: UInt64, count: Int) -> Data? {
		guard count > 0, address != 0 else { return nil }
		var data = Data(count: count)
		let complete = data.withUnsafeMutableBytes { buffer -> Bool in
			guard let base = buffer.baseAddress else { return false }
			var outsize: vm_size_t = 0
			let result = vm_read_overwrite(task, vm_address_t(truncatingIfNeeded: address), vm_size_t(count),
			                               vm_address_t(bitPattern: base), &outsize)
			return result == KERN_SUCCESS && Int(outsize) == count
		}
		return complete ? data : nil
	}

	public func read<T>(_ type: T.Type, at address: UInt64) -> T? {
		read(address, count: MemoryLayout<T>.size)?.load(type, at: 0)
	}

	/// A NUL-terminated string, read a piece at a time so a string that ends
	/// just before an unmapped page is still read whole.
	public func readCString(at address: UInt64, limit: Int = 4096) -> String? {
		guard address != 0 else { return nil }
		var bytes: [UInt8] = []
		var cursor = address
		while bytes.count < limit {
			// Up to the end of the page, never past it: the next page may not exist.
			let page = UInt64(4096)
			let room = Int(page - (cursor % page))
			let want = min(room, limit - bytes.count)
			guard let chunk = read(cursor, count: want) else { break }
			if let nul = chunk.firstIndex(of: 0) {
				bytes.append(contentsOf: chunk[chunk.startIndex..<nul])
				return String(decoding: bytes, as: UTF8.self)
			}
			bytes.append(contentsOf: chunk)
			cursor += UInt64(want)
		}
		return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
	}
}

extension Data {
	func load<T>(_ type: T.Type, at offset: Int) -> T {
		withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
	}

	/// A fixed 16-byte Mach-O name field.
	func machOName(at offset: Int) -> String {
		let field = self[(startIndex + offset)..<Swift.min(endIndex, startIndex + offset + 16)]
		return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
	}
}
