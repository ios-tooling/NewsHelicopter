//
//  AutopsyReport.swift
//  Autopsy
//
//  Everything the extension learned from the corpse, in one Codable value.
//  Addresses are kept whole (UInt64), never rounded through a Double: a
//  symbolicator that is off by one is off by a function.
//

import Foundation

public struct AutopsyReport: Codable, Sendable, Identifiable {
	public static let formatVersion = 1

	public var formatVersion = Self.formatVersion
	public let id: UUID
	/// When the extension ran — moments after the crash, not the crash itself.
	public let capturedAt: Date
	public let app: App
	public let reason: Reason
	public let images: [Image]
	public let threads: [Thread]
	/// What the crashed process had told the crash reporter: a Swift fatal
	/// error's text, an abort message, a dyld complaint.
	public let annotations: [Annotation]
	/// The app's own breadcrumbs, if its executable carries the block.
	public let crumbs: Crumbs?
	/// How long the extension took, so its budget can be learned rather than guessed.
	public let elapsedMilliseconds: Double

	public init(id: UUID = UUID(), capturedAt: Date = .now, app: App, reason: Reason, images: [Image], threads: [Thread],
	            annotations: [Annotation], crumbs: Crumbs?, elapsedMilliseconds: Double) {
		self.id = id
		self.capturedAt = capturedAt
		self.app = app
		self.reason = reason
		self.images = images
		self.threads = threads
		self.annotations = annotations
		self.crumbs = crumbs
		self.elapsedMilliseconds = elapsedMilliseconds
	}

	public struct App: Codable, Sendable {
		public let bundleID: String?
		public let version: String?
		public let build: String?
		public let executable: String?
		public let osVersion: String
		public init(bundleID: String?, version: String?, build: String?, executable: String?, osVersion: String) {
			self.bundleID = bundleID; self.version = version; self.build = build; self.executable = executable; self.osVersion = osVersion
		}
	}

	public struct Reason: Codable, Sendable {
		/// The Mach exception (EXC_BAD_ACCESS = 1, EXC_BREAKPOINT = 6, …) and its codes.
		public let exception: Int32
		public let codes: [UInt64]
		/// The exception's name, and the signal it would have been delivered as.
		public let exceptionName: String
		public let signalName: String?
		public init(exception: Int32, codes: [UInt64], exceptionName: String, signalName: String?) {
			self.exception = exception; self.codes = codes; self.exceptionName = exceptionName; self.signalName = signalName
		}
	}

	public struct Image: Codable, Sendable {
		public let path: String
		public let uuid: UUID?
		public let baseAddress: UInt64
		public let size: UInt64
		public init(path: String, uuid: UUID?, baseAddress: UInt64, size: UInt64) {
			self.path = path; self.uuid = uuid; self.baseAddress = baseAddress; self.size = size
		}
		public var name: String { (path as NSString).lastPathComponent }
	}

	public struct Thread: Codable, Sendable {
		public let index: Int
		public let id: UInt64
		public let name: String?
		public let queueName: String?
		public let isCrashed: Bool
		public let frames: [Frame]
		/// pc, lr, sp, fp, far, esr — named so a report reads without a decoder ring.
		public let registers: [String: UInt64]
		public init(index: Int, id: UInt64, name: String?, queueName: String?, isCrashed: Bool, frames: [Frame], registers: [String: UInt64]) {
			self.index = index; self.id = id; self.name = name; self.queueName = queueName; self.isCrashed = isCrashed
			self.frames = frames; self.registers = registers
		}
	}

	public struct Frame: Codable, Sendable {
		public let address: UInt64
		/// Index into `images`, and the address's offset into that image.
		public let imageIndex: Int?
		public let offsetInImage: UInt64?
		/// What the system symbolicated on the device, inline frames expanded
		/// innermost first; empty when nothing was known for the address.
		public let symbols: [Symbol]
		public init(address: UInt64, imageIndex: Int?, offsetInImage: UInt64?, symbols: [Symbol]) {
			self.address = address; self.imageIndex = imageIndex; self.offsetInImage = offsetInImage; self.symbols = symbols
		}
	}

	public struct Symbol: Codable, Sendable {
		public let name: String
		public let offset: UInt64
		public let file: String?
		public let line: Int?
		public let isInline: Bool
		public init(name: String, offset: UInt64, file: String?, line: Int?, isInline: Bool) {
			self.name = name; self.offset = offset; self.file = file; self.line = line; self.isInline = isInline
		}
	}

	public struct Annotation: Codable, Sendable {
		public let image: String
		public let message: String?
		public let message2: String?
		public let signature: String?
		public let abortCause: UInt64
		public init(image: String, message: String?, message2: String?, signature: String?, abortCause: UInt64) {
			self.image = image; self.message = message; self.message2 = message2; self.signature = signature; self.abortCause = abortCause
		}
		/// The line a person would want first.
		public var text: String? { [message, message2].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n").nonEmpty }
	}

	public struct Crumbs: Codable, Sendable, Equatable {
		public let runID: String?
		public let screen: String?
		/// Oldest first.
		public let lines: [String]
		public init(runID: String?, screen: String?, lines: [String]) {
			self.runID = runID; self.screen = screen; self.lines = lines
		}
	}

	public var crashedThread: Thread? { threads.first { $0.isCrashed } }
	/// The first annotation with something to say — for a Swift trap, the fatal error.
	public var headline: String? { annotations.lazy.compactMap(\.text).first }
}

extension String {
	var nonEmpty: String? { isEmpty ? nil : self }
}
