//
//  AutopsyReportStore.swift
//  Autopsy
//
//  Where reports wait between the extension that writes them and the app that
//  sends them: one JSON file each in a directory both can reach — an app
//  group's, in practice. Writes land whole (a temporary name, then a rename),
//  so the app never reads half a report.
//

import Foundation

public struct AutopsyReportStore: Sendable {
	public let directory: URL

	public init(directory: URL) {
		self.directory = directory
	}

	/// The store inside an app group container, at `path` under its root.
	public init?(appGroup: String, path: String = "Autopsy") {
		guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
		self.init(directory: container.appendingPathComponent(path, isDirectory: true))
	}

	private static var encoder: JSONEncoder {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.sortedKeys]
		return encoder
	}

	private static var decoder: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}

	public func url(for id: UUID) -> URL {
		directory.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("json")
	}

	public func write(_ report: AutopsyReport) throws {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let data = try Self.encoder.encode(report)
		let final = url(for: report.id)
		let staging = final.appendingPathExtension("partial")
		try data.write(to: staging, options: [.atomic])
		_ = try FileManager.default.replaceItemAt(final, withItemAt: staging)
	}

	/// Every readable report, oldest capture first. A file this build cannot
	/// decode is skipped, not deleted: a newer format is somebody else's to read.
	public func reports() -> [AutopsyReport] {
		guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
		return urls.filter { $0.pathExtension == "json" }
			.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(AutopsyReport.self, from: $0) } }
			.sorted { $0.capturedAt < $1.capturedAt }
	}

	public func remove(_ report: AutopsyReport) {
		try? FileManager.default.removeItem(at: url(for: report.id))
	}
}
