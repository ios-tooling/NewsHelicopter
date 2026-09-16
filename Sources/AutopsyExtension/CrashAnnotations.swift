//
//  CrashAnnotations.swift
//  AutopsyExtension
//
//  What a process tells the crash reporter before it dies. The Swift runtime
//  writes a fatal error's text here, libc an abort's reason, dyld a missing
//  library's name: each keeps a `crashreporter_annotations_t` in a
//  `__crash_info` section, and Apple's own report prints it as "Application
//  Specific Information". Reading it from the corpse is how a crash extension
//  learns *what* the fatal error said, not merely that there was one.
//

import Foundation

public enum CrashAnnotations {
	/// `crashreporter_annotations_t`, version 4 and later: eight 64-bit fields.
	static let minimumSize = 8 * 5

	public struct Annotation: Sendable, Equatable {
		public let image: String
		public let message: String?
		public let message2: String?
		public let signature: String?
		public let abortCause: UInt64
	}

	/// The annotations of every image that has any. Images whose section is
	/// present but says nothing — most of them, in a healthy process — are
	/// left out.
	public static func read(images: [(name: String, baseAddress: UInt64)], memory: TaskMemory) -> [Annotation] {
		images.compactMap { image in
			MachOImage(memory: memory, baseAddress: image.baseAddress).flatMap { read(image: $0, named: image.name) }
		}
	}

	/// One image's annotation, if it has anything to say.
	public static func read(image machO: MachOImage, named name: String) -> Annotation? {
		guard let section = machO.section("__crash_info"), section.size >= UInt64(minimumSize),
		      let data = machO.contents(of: section) else { return nil }
		let memory = machO.memory
		let version = data.load(UInt64.self, at: 0)
		guard version >= 4 else { return nil }
		let message = memory.readCString(at: data.load(UInt64.self, at: 8))
		let signature = memory.readCString(at: data.load(UInt64.self, at: 16))
		let message2 = memory.readCString(at: data.load(UInt64.self, at: 32))
		let abortCause = data.count >= 64 ? data.load(UInt64.self, at: 56) : 0
		guard message?.isEmpty == false || message2?.isEmpty == false else { return nil }
		return Annotation(image: name, message: message, message2: message2, signature: signature, abortCause: abortCause)
	}
}
