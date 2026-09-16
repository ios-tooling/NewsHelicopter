//
//  NewsHelicopterReporter.swift
//  NewsHelicopterExtension
//
//  The one piece that needs Apple's framework: a `CrashedProcess` in, a
//  report in the store out. An extension's whole `processCrashReport` is a
//  call to this.
//
//  Nothing here talks to the network. The extension's lifetime is short and
//  undocumented; a file in the app group is what survives it, and the app's
//  own uploader sends it on the next launch.
//

#if canImport(CrashReportExtension)
import NewsHelicopter
import CrashReportExtension
import Foundation
import os

@available(iOS 27.0, macOS 27.0, *)
public struct NewsHelicopterReporter {
	public let store: NewsHelicopterReportStore
	public var frameLimit = ThreadWalker.defaultFrameLimit
	public var threadLimit = ThreadWalker.defaultThreadLimit
	private let log: Logger

	public init(store: NewsHelicopterReportStore, logSubsystem: String = "NewsHelicopter") {
		self.store = store
		self.log = Logger(subsystem: logSubsystem, category: "extension")
	}

	/// Read the corpse and file the report. Returns it, or nil if the store
	/// refused the write — which is logged, since there is nobody else to tell.
	@discardableResult
	public func process(_ process: CrashedProcess) -> NewsHelicopterReport? {
		let report = report(for: process)
		log.notice("Crash: \(report.reason.exceptionName, privacy: .public) \(report.headline ?? "", privacy: .public); \(report.threads.count) threads in \(report.elapsedMilliseconds, privacy: .public) ms")
		do {
			try store.write(report)
			return report
		} catch {
			log.error("Could not write the crash report: \(String(describing: error), privacy: .public)")
			return nil
		}
	}

	/// The report alone, for a caller that stores it some other way.
	public func report(for process: CrashedProcess) -> NewsHelicopterReport {
		let reason = process.reason
		var builder = NewsHelicopterReportBuilder(
			memory: TaskMemory(task: process.corpsePort),
			images: process.binaryImages.map { NewsHelicopterReportBuilder.Image(path: $0.path, uuid: $0.uuid, baseAddress: $0.baseAddress, size: $0.size) },
			reason: NewsHelicopterReport.Reason(exception: reason.exception, codes: reason.codes,
			                             exceptionName: ExceptionNames.name(reason.exception),
			                             signalName: ExceptionNames.signalName(exception: reason.exception, codes: reason.codes)),
			symbolicate: { addresses in
				process.symbolicateAddresses(addresses).map { frames in
					frames.map { NewsHelicopterReport.Symbol(name: $0.symbol, offset: $0.symbolOffset, file: $0.sourceFile, line: $0.sourceLine, isInline: $0.isInline) }
				}
			})
		builder.frameLimit = frameLimit
		builder.threadLimit = threadLimit
		return builder.build()
	}
}
#endif
