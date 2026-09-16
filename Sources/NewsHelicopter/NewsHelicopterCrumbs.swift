//
//  NewsHelicopterCrumbs.swift
//  NewsHelicopter
//
//  What the app says about itself while it runs, for the extension to read
//  back out of the corpse: which launch this is, where the reader is, and the
//  last few things that happened. Cheap enough to call anywhere — each call is
//  a bounded string copy into a static block.
//

import NewsHelicopterCrumbs
import Foundation

public enum NewsHelicopterCrumbs {
	/// How many lines the ring keeps.
	public static let lineCount = Int(NEWS_HELICOPTER_LINE_COUNT)

	/// Stamp this launch with a fresh id and return it. Call once, early: a
	/// report carries the id, so the app can tell which run it came from.
	@discardableResult
	public static func beginRun(id: String = UUID().uuidString) -> String {
		id.withCString { news_helicopter_crumbs_set_run_id($0) }
		return id
	}

	/// Where the reader is now. Overwrites; the ring is for what happened.
	public static func setScreen(_ screen: String) {
		screen.withCString { news_helicopter_crumbs_set_screen($0) }
	}

	/// Add a line to the ring — an event, a phase, a decision. Long lines are
	/// cut to the field, not refused.
	public static func note(_ line: String) {
		line.withCString { news_helicopter_crumbs_append($0) }
	}

	/// The block as the app itself sees it: what a crash report would carry
	/// if it happened now. For tests and for showing the reader.
	public static func snapshot() -> NewsHelicopterReport.Crumbs {
		let data = Data(bytes: UnsafeRawPointer(news_helicopter_crumbs_pointer()), count: MemoryLayout<news_helicopter_crumbs_t>.size)
		return NewsHelicopterCrumbsLayout.decode(data) ?? NewsHelicopterReport.Crumbs(runID: nil, screen: nil, lines: [])
	}
}

/// The block's layout by offset, shared with the extension's reader — which
/// has only bytes it copied out of another process, never the C type.
public enum NewsHelicopterCrumbsLayout {
	public static let magic = UInt64(NEWS_HELICOPTER_CRUMBS_MAGIC)
	public static let version = UInt32(NEWS_HELICOPTER_CRUMBS_VERSION)
	public static let segment = NEWS_HELICOPTER_CRUMBS_SEGMENT
	public static let section = NEWS_HELICOPTER_CRUMBS_SECTION
	public static let size = MemoryLayout<news_helicopter_crumbs_t>.size

	/// Decode a copy of the block. Nil unless the magic and version match: a
	/// build carrying a different layout is left unread rather than misread.
	public static func decode(_ data: Data) -> NewsHelicopterReport.Crumbs? {
		let headerSize = 8 + 4 * 4
		guard data.count >= headerSize, data.load(UInt64.self, at: 0) == magic, data.load(UInt32.self, at: 8) == version else { return nil }
		let lineLength = Int(data.load(UInt32.self, at: 12))
		let lineCount = Int(data.load(UInt32.self, at: 16))
		let written = Int(data.load(UInt32.self, at: 20))
		let runIDLength = Int(NEWS_HELICOPTER_RUN_ID_LENGTH), screenLength = Int(NEWS_HELICOPTER_SCREEN_LENGTH)
		guard lineLength > 0, lineCount > 0, data.count >= headerSize + runIDLength + screenLength + lineLength * lineCount else { return nil }
		let runID = data.cString(at: headerSize, max: runIDLength)
		let screen = data.cString(at: headerSize + runIDLength, max: screenLength)
		let linesStart = headerSize + runIDLength + screenLength
		// Oldest first: the ring's next slot is the oldest line once it has wrapped.
		let count = min(written, lineCount)
		let first = written > lineCount ? written % lineCount : 0
		let lines = (0..<count).map { index -> String in
			let slot = (first + index) % lineCount
			return data.cString(at: linesStart + slot * lineLength, max: lineLength)
		}
		return NewsHelicopterReport.Crumbs(runID: runID.isEmpty ? nil : runID, screen: screen.isEmpty ? nil : screen, lines: lines)
	}
}

extension Data {
	func load<T>(_ type: T.Type, at offset: Int) -> T {
		withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
	}

	/// A NUL-terminated string in a fixed field; whatever sits past the field
	/// or after the first NUL is not part of it.
	func cString(at offset: Int, max: Int) -> String {
		let field = self[(startIndex + offset)..<Swift.min(endIndex, startIndex + offset + max)]
		let bytes = field.prefix { $0 != 0 }
		return String(decoding: bytes, as: UTF8.self)
	}
}
