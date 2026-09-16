//
//  NewsHelicopterTests.swift
//  NewsHelicopterTests
//
//  The engine reads a task's memory; the current task is a task. So the
//  crumbs, the Mach-O walk, the thread walk and the whole report are
//  exercised for real here, against this process, with only the corpse and
//  the symbolicator stood in for.
//

import NewsHelicopter
import NewsHelicopterCrumbs
import NewsHelicopterExtension
import Darwin
import Foundation
import MachO
import Testing

@Suite("NewsHelicopter", .serialized)
struct NewsHelicopterTests {
	// -------------------------------------------------------------- crumbs

	@Test("the crumbs block records the run, the screen and the last lines in order")
	func crumbsRoundTrip() {
		let run = NewsHelicopterCrumbs.beginRun(id: "run-1234")
		NewsHelicopterCrumbs.setScreen("Library")
		for index in 0..<(NewsHelicopterCrumbs.lineCount + 6) { NewsHelicopterCrumbs.note("line \(index)") }
		let crumbs = NewsHelicopterCrumbs.snapshot()
		#expect(crumbs.runID == run)
		#expect(crumbs.screen == "Library")
		#expect(crumbs.lines.count == NewsHelicopterCrumbs.lineCount)
		#expect(crumbs.lines.first == "line 6")
		#expect(crumbs.lines.last == "line \(NewsHelicopterCrumbs.lineCount + 5)")
	}

	@Test("a block from another layout is left unread")
	func foreignLayoutIsRefused() {
		var data = Data(count: NewsHelicopterCrumbsLayout.size)
		data.withUnsafeMutableBytes { $0.storeBytes(of: UInt64(0x1234), as: UInt64.self) }
		#expect(NewsHelicopterCrumbsLayout.decode(data) == nil)
	}

	// ------------------------------------------------------------- Mach-O

	@Test("the crumbs section is found in this process's image and reads back the same")
	func crumbsReadThroughTheSection() throws {
		NewsHelicopterCrumbs.setScreen("Section test")
		NewsHelicopterCrumbs.note("read me back")
		let image = try #require(Self.imageContaining(UInt64(UInt(bitPattern: news_helicopter_crumbs_pointer()))))
		let machO = try #require(MachOImage(memory: .current, baseAddress: image.base))
		let section = try #require(machO.section(NewsHelicopterCrumbsLayout.section, in: NewsHelicopterCrumbsLayout.segment))
		#expect(section.address == UInt64(UInt(bitPattern: news_helicopter_crumbs_pointer())), "the slid section address is the block's")
		let crumbs = try #require(CrumbsReader.read(executableAt: image.base, memory: .current))
		#expect(crumbs == NewsHelicopterCrumbs.snapshot())
	}

	@Test("every loaded image parses, and the Swift runtime carries a crash-info section")
	func imagesParse() throws {
		let images = Self.images()
		#expect(images.count > 10)
		for image in images { #expect(MachOImage(memory: .current, baseAddress: image.base) != nil, Comment(rawValue: image.path)) }
		let swiftCore = try #require(images.first { $0.path.hasSuffix("libswiftCore.dylib") })
		let machO = try #require(MachOImage(memory: .current, baseAddress: swiftCore.base))
		#expect(machO.section("__crash_info") != nil)
		#expect(machO.uuid != nil)
		// A process that has not crashed has nothing to say.
		#expect(CrashAnnotations.read(images: [(name: "libswiftCore.dylib", baseAddress: swiftCore.base)], memory: .current).isEmpty)
	}

	// ------------------------------------------------------------ threads

	@Test("walking this task finds a parked thread and the call chain it is parked in")
	func threadWalk() throws {
		// The walker's own thread cannot be walked from its register snapshot:
		// by the time the stack is read, the frames the snapshot points at
		// have been popped. A corpse's stacks stand still; so does a thread
		// waiting on a semaphore, nine calls deep.
		let parked = DispatchSemaphore(value: 0), ready = DispatchSemaphore(value: 0)
		let thread = Thread {
			Thread.current.name = "helicopter-parked"
			ParkedChain.descend(9) { ready.signal(); parked.wait() }
		}
		thread.start()
		ready.wait()
		defer { parked.signal() }
		usleep(20_000)		// let it reach the wait
		let target = try #require(ThreadWalker.threads(of: .current).first { $0.name == "helicopter-parked" })
		#expect(target.registers["pc"] != nil)
		#expect(target.frames.count >= 12, "nine descents, the closure, the wait and its callers: \(target.frames.count)")
		// The bundle's binary is the one the crumbs block was linked into.
		let bundle = try #require(Self.imageContaining(UInt64(UInt(bitPattern: news_helicopter_crumbs_pointer()))))
		let text = try #require(MachOImage(memory: .current, baseAddress: bundle.base)?.segments.first { $0.name == "__TEXT" })
		let ours = target.frames.filter { $0 >= text.address && $0 < text.address + text.size }
		#expect(ours.count >= 9, "the descents are frames in this bundle: \(ours.count)")
		#expect(target.frames == ThreadWalker.threads(of: .current).first { $0.name == "helicopter-parked" }?.frames, "a parked thread walks the same twice")
	}

	// ------------------------------------------------------------- report

	@Test("a report of this task names the executable, threads, images and crumbs, and survives the store")
	func reportBuildsAndStores() throws {
		NewsHelicopterCrumbs.setScreen("Report test")
		let reason = NewsHelicopterReport.Reason(exception: EXC_BREAKPOINT, codes: [1, 0], exceptionName: "EXC_BREAKPOINT", signalName: "SIGTRAP")
		let builder = NewsHelicopterReportBuilder(memory: .current, images: Self.builderImages(), reason: reason) { addresses in
			addresses.map { [NewsHelicopterReport.Symbol(name: "sym_\($0)", offset: 0, file: nil, line: nil, isInline: false)] }
		}
		let report = builder.build()
		#expect(report.app.executable != nil)
		#expect(!report.threads.isEmpty)
		#expect(report.threads.contains { $0.isCrashed })
		#expect(report.images.map(\.baseAddress) == report.images.map(\.baseAddress).sorted())
		#expect(report.crumbs?.screen == "Report test")
		#expect(report.elapsedMilliseconds > 0)
		let frame = try #require(report.threads.flatMap(\.frames).first { $0.imageIndex != nil })
		#expect(frame.offsetInImage == frame.address - report.images[frame.imageIndex!].baseAddress)
		#expect(frame.symbols.first?.name == "sym_\(frame.address)")

		let store = NewsHelicopterReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("helicopter-\(UUID().uuidString)"))
		try store.write(report)
		let stored = store.reports()
		#expect(stored.count == 1)
		#expect(stored.first?.id == report.id)
		#expect(stored.first?.threads.count == report.threads.count)
		#expect(stored.first?.crumbs == report.crumbs)
		store.remove(report)
		#expect(store.reports().isEmpty)
	}

	@Test("Mach exceptions name their signal")
	func signals() {
		#expect(ExceptionNames.signalName(exception: EXC_BAD_ACCESS, codes: [UInt64(KERN_INVALID_ADDRESS), 0]) == "SIGSEGV")
		#expect(ExceptionNames.signalName(exception: EXC_BAD_ACCESS, codes: [UInt64(KERN_PROTECTION_FAILURE), 0]) == "SIGBUS")
		#expect(ExceptionNames.signalName(exception: EXC_BREAKPOINT, codes: [1, 0]) == "SIGTRAP")
		#expect(ExceptionNames.signalName(exception: EXC_CRASH, codes: [UInt64(SIGABRT) << 24, 0]) == "SIGABRT")
		#expect(ExceptionNames.name(EXC_GUARD) == "EXC_GUARD")
	}

	// ------------------------------------------------------------ helpers

	enum ParkedChain {
		@inline(never) static func descend(_ depth: Int, then park: () -> Void) {
			if depth == 0 { park() } else { descend(depth - 1, then: park) }
			withExtendedLifetime(depth) {}
		}
	}

	struct LoadedImage { let path: String; let base: UInt64 }

	static func images() -> [LoadedImage] {
		(0..<_dyld_image_count()).compactMap { index in
			guard let header = _dyld_get_image_header(index), let name = _dyld_get_image_name(index) else { return nil }
			return LoadedImage(path: String(cString: name), base: UInt64(UInt(bitPattern: header)))
		}
	}

	static func imageContaining(_ address: UInt64) -> LoadedImage? {
		images().filter { $0.base <= address }.max { $0.base < $1.base }
	}

	/// This process's images with the size of their code segment, which is
	/// where every frame address falls.
	static func builderImages() -> [NewsHelicopterReportBuilder.Image] {
		images().compactMap { image in
			guard let machO = MachOImage(memory: .current, baseAddress: image.base),
			      let text = machO.segments.first(where: { $0.name == "__TEXT" }) else { return nil }
			return NewsHelicopterReportBuilder.Image(path: image.path, uuid: machO.uuid, baseAddress: image.base, size: text.size)
		}
	}
}
