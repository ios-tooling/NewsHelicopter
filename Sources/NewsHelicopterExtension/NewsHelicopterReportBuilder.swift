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
		let parsed = sorted.map { MachOImage(memory: memory, baseAddress: $0.baseAddress) }
		let executable = zip(sorted, parsed).first { $1?.isExecutable == true }?.0
		let snapshots = ThreadWalker.threads(of: memory, frameLimit: frameLimit, threadLimit: threadLimit)
		let addresses = Array(Set(snapshots.flatMap(\.frames))).sorted()
		let symbols = Dictionary(uniqueKeysWithValues: zip(addresses, symbolicate(addresses)))
		var threads = snapshots.enumerated().map { index, snapshot in
			NewsHelicopterReport.Thread(index: index, id: snapshot.id, name: snapshot.name, queueName: nil, isCrashed: false,
			                     frames: snapshot.frames.map { frame(at: $0, images: sorted, symbols: symbols[$0] ?? []) },
			                     registers: snapshot.registers)
		}
		if let crashed = crashedIndex(snapshots: snapshots, threads: threads) {
			let thread = threads[crashed]
			threads[crashed] = NewsHelicopterReport.Thread(index: thread.index, id: thread.id, name: thread.name, queueName: thread.queueName,
			                                        isCrashed: true, frames: thread.frames, registers: thread.registers)
		}
		let annotations = zip(sorted, parsed).compactMap { image, machO in
			machO.flatMap { CrashAnnotations.read(image: $0, named: (image.path as NSString).lastPathComponent) }
		}.map { NewsHelicopterReport.Annotation(image: $0.image, message: $0.message, message2: $0.message2, signature: $0.signature, abortCause: $0.abortCause) }
		// The app's executable carries the block; a test host's does not, and
		// its bundle's binary does, so any image will do.
		let crumbs = parsed.lazy.compactMap { $0 }.compactMap(CrumbsReader.read(image:)).first
		let elapsed = ContinuousClock.now - started
		return NewsHelicopterReport(app: appInfo(executable: executable), reason: reason,
		                     images: sorted.map { NewsHelicopterReport.Image(path: $0.path, uuid: $0.uuid, baseAddress: $0.baseAddress, size: $0.size) },
		                     threads: threads, annotations: annotations, crumbs: crumbs,
		                     elapsedMilliseconds: Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
	}

	func frame(at address: UInt64, images: [Image], symbols: [NewsHelicopterReport.Symbol]) -> NewsHelicopterReport.Frame {
		// The image whose range holds the address; images are sorted by base.
		var low = 0, high = images.count - 1, found: Int?
		while low <= high {
			let middle = (low + high) / 2
			let image = images[middle]
			if address < image.baseAddress { high = middle - 1 }
			else if address >= image.baseAddress + image.size { low = middle + 1 }
			else { found = middle; break }
		}
		return NewsHelicopterReport.Frame(address: address, imageIndex: found,
		                           offsetInImage: found.map { address - images[$0].baseAddress }, symbols: symbols)
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
