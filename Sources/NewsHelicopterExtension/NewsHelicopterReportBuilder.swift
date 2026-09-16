//
//  NewsHelicopterReportBuilder.swift
//  NewsHelicopterExtension
//
//  Assembles a report from a task's memory, its images and a symbolicator.
//  Everything here runs against any task, so it can be exercised on the
//  current one; only the caller knows whether the task is a corpse.
//

import NewsHelicopter
import Foundation

public struct NewsHelicopterReportBuilder {
	public struct Image: Sendable {
		public let path: String
		public let uuid: UUID?
		public let baseAddress: UInt64
		public let size: UInt64
		public init(path: String, uuid: UUID?, baseAddress: UInt64, size: UInt64) {
			self.path = path; self.uuid = uuid; self.baseAddress = baseAddress; self.size = size
		}
	}

	public typealias Symbolicator = ([UInt64]) -> [[NewsHelicopterReport.Symbol]]

	public let memory: TaskMemory
	public let images: [Image]
	public let reason: NewsHelicopterReport.Reason
	public let symbolicate: Symbolicator
	public var frameLimit = ThreadWalker.defaultFrameLimit
	public var threadLimit = ThreadWalker.defaultThreadLimit

	public init(memory: TaskMemory, images: [Image], reason: NewsHelicopterReport.Reason, symbolicate: @escaping Symbolicator) {
		self.memory = memory
		self.images = images
		self.reason = reason
		self.symbolicate = symbolicate
	}

	public func build() -> NewsHelicopterReport {
		let started = ContinuousClock.now
		let sorted = images.sorted { $0.baseAddress < $1.baseAddress }
		// One pass, each image parsed and let go in turn: a corpse maps well over
		// a thousand images, and their load commands together outweigh the few
		// megabytes an extension is allowed before jetsam takes it.
		var executable: Int?
		var annotations: [NewsHelicopterReport.Annotation] = []
		var crumbs: NewsHelicopterReport.Crumbs?
		for (index, image) in sorted.enumerated() {
			guard let machO = MachOImage(memory: memory, baseAddress: image.baseAddress) else { continue }
			if executable == nil, machO.isExecutable { executable = index }
			if let found = CrashAnnotations.read(image: machO, named: (image.path as NSString).lastPathComponent) {
				annotations.append(NewsHelicopterReport.Annotation(image: found.image, message: found.message, message2: found.message2,
				                                                    signature: found.signature, abortCause: found.abortCause))
			}
			// The app's executable carries the block; a test host's does not, and
			// its bundle's binary does, so any image will do.
			if crumbs == nil { crumbs = CrumbsReader.read(image: machO) }
		}
		let snapshots = ThreadWalker.threads(of: memory, frameLimit: frameLimit, threadLimit: threadLimit)
		let addresses = Array(Set(snapshots.flatMap(\.frames))).sorted()
		let symbols = Dictionary(uniqueKeysWithValues: zip(addresses, symbolicate(addresses)))
		// Only the images a frame lands in ride along, plus the executable:
		// nobody reading the report wants the other fourteen hundred.
		let located = Dictionary(uniqueKeysWithValues: addresses.map { ($0, locate($0, in: sorted)) })
		let table = ImageTable(indices: Set(located.values.compactMap { $0 } + [executable].compactMap { $0 }))
		var threads = snapshots.enumerated().map { index, snapshot in
			NewsHelicopterReport.Thread(index: index, id: snapshot.id, name: snapshot.name, queueName: nil, isCrashed: false,
			                            frames: frames(of: snapshot, symbols: symbols).map { frame(at: $0, in: sorted, located: located[$0] ?? nil, table: table, symbols: symbols) },
			                            registers: snapshot.registers)
		}
		if let crashed = crashedIndex(snapshots: snapshots, threads: threads) {
			let thread = threads[crashed]
			threads[crashed] = NewsHelicopterReport.Thread(index: thread.index, id: thread.id, name: thread.name, queueName: thread.queueName,
			                                               isCrashed: true, frames: thread.frames, registers: thread.registers)
		}
		let elapsed = ContinuousClock.now - started
		return NewsHelicopterReport(app: appInfo(executable: executable.map { sorted[$0] }), reason: reason,
		                            images: table.sortedIndices.map { NewsHelicopterReport.Image(path: sorted[$0].path, uuid: sorted[$0].uuid,
		                                                                                         baseAddress: sorted[$0].baseAddress, size: sorted[$0].size) },
		                            threads: threads, annotations: annotations, crumbs: crumbs,
		                            elapsedMilliseconds: Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15,
		                            memoryFootprintBytes: ProcessFootprint.bytes)
	}

	/// The faulting thread when the kernel marked one; else the thread that
	/// raised the signal, recognisable by what it was calling; else the main
	/// thread, which is at least where a hang would be.
	func crashedIndex(snapshots: [ThreadSnapshot], threads: [NewsHelicopterReport.Thread]) -> Int? {
		if let faulted = snapshots.firstIndex(where: \.faulted) { return faulted }
		let raisers: Set<String> = ["__pthread_kill", "abort", "__abort_with_payload", "pthread_kill", "raise"]
		if let raiser = threads.firstIndex(where: { thread in thread.frames.contains { $0.symbols.contains { raisers.contains($0.name) } } }) {
			return raiser
		}
		return threads.isEmpty ? nil : 0
	}

	/// The crashed app's identity, read from the bundle around its executable:
	/// `X.app/X` on iOS, `X.app/Contents/MacOS/X` on the Mac.
	func appInfo(executable: Image?) -> NewsHelicopterReport.App {
		let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
		guard let executable else { return NewsHelicopterReport.App(bundleID: nil, version: nil, build: nil, executable: nil, osVersion: osVersion) }
		let url = URL(fileURLWithPath: executable.path)
		let name = url.lastPathComponent
		let candidates = [url.deletingLastPathComponent(),
		                  url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()]
		let info = candidates.lazy.compactMap { Bundle(url: $0)?.infoDictionary }.first { $0["CFBundleIdentifier"] != nil }
		return NewsHelicopterReport.App(bundleID: info?["CFBundleIdentifier"] as? String,
		                         version: info?["CFBundleShortVersionString"] as? String,
		                         build: info?["CFBundleVersion"] as? String,
		                         executable: name, osVersion: osVersion)
	}
}
