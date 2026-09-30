//
//  AsyncWalkTests.swift
//  NewsHelicopterTests
//
//  The async hop of the thread walk: once against a hand-laid frame and
//  context chain, and once against a real task parked three async calls deep.
//

@testable import NewsHelicopterExtension
import Darwin
import Foundation
import Testing

@Suite("Async stack walk", .serialized)
struct AsyncWalkTests {
	@Test("an async frame record hands the walk to its task's context chain")
	func laidOutChain() {
		let memory = LaidOut()
		defer { memory.free() }
		// A sync frame at `a` calls into async `b`; b's record points at the executor.
		memory.store(at: 0x00, memory.address(0x40), 0x1000)
		memory.store(at: 0x38, memory.address(0x80))
		memory.store(at: 0x40, memory.address(0x100) | 0x1000_0000_0000_0000, 0x2000)
		memory.store(at: 0x80, memory.address(0xA0), 0x3000)
		memory.store(at: 0xA0, 0, 0x4000)
		let walked = ThreadWalker.walk(pc: 0x10, lr: 0x1000, fp: memory.address(0), memory: .current, limit: 64)
		#expect(walked.frames == [0x10, 0x1000, 0x3001, 0x4001], "no executor frame; each resume point one past its entry")
		#expect(!walked.usedLinkRegister)

		let atAsync = ThreadWalker.walk(pc: 0x10, lr: 0x2000, fp: memory.address(0x40), memory: .current, limit: 64)
		#expect(atAsync.frames == [0x10, 0x3001, 0x4001], "an async function's saved lr is its executor, never a caller")
		#expect(ThreadWalker.walk(pc: 0x10, lr: 0x1000, fp: memory.address(0), memory: .current, limit: 3).frames == [0x10, 0x1000, 0x3001], "the limit caps the whole walk")
	}

	@Test("a context chain that loops back on itself ends")
	func loopingChain() {
		let memory = LaidOut()
		defer { memory.free() }
		memory.store(at: 0x00, memory.address(0x10), 0x3000)
		memory.store(at: 0x10, memory.address(0x00), 0x4000)
		#expect(ThreadWalker.asyncCallers(context: memory.address(0), memory: .current, limit: 64) == [0x3001, 0x4001])
	}

	@Test("a task parked three async calls deep walks back through every caller")
	func realTask() throws {
		let parked = Parked()
		Task.detached { await AsyncChain.outer(parked) }
		parked.ready.wait()
		defer { parked.release.signal() }
		let thread = try #require(ThreadWalker.threads(of: .current).first { $0.id == parked.threadID })
		let names = thread.frames.dropFirst().compactMap { Self.symbolName($0 - 1) }
		for function in ["5inner", "6middle", "5outer"] {
			#expect(names.contains { $0.contains("AsyncChain") && $0.contains(function) }, "\(function) in \(names)")
		}
	}

	static func symbolName(_ address: UInt64) -> String? {
		var info = Dl_info()
		guard dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0, let name = info.dli_sname else { return nil }
		return String(cString: name)
	}
}

/// Parks the task's thread until the test has walked it.
final class Parked: @unchecked Sendable {
	let ready = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
	var threadID: UInt64 = 0

	func park() {
		pthread_threadid_np(nil, &threadID)
		ready.signal()
		release.wait()
	}
}

enum AsyncChain {
	@inline(never) static func outer(_ parked: Parked) async { await middle(parked); withExtendedLifetime(parked) {} }
	@inline(never) static func middle(_ parked: Parked) async { await inner(parked); withExtendedLifetime(parked) {} }
	@inline(never) static func inner(_ parked: Parked) async { await Task.yield(); parked.park() }
}

/// A scratch page of words to lay frame records and contexts out in.
struct LaidOut {
	let base = UnsafeMutableRawPointer.allocate(byteCount: 0x200, alignment: 16)

	init() { base.initializeMemory(as: UInt8.self, repeating: 0, count: 0x200) }

	func address(_ offset: Int) -> UInt64 { UInt64(UInt(bitPattern: base + offset)) }
	func store(at offset: Int, _ words: UInt64...) {
		for (index, word) in words.enumerated() { base.storeBytes(of: word, toByteOffset: offset + index * 8, as: UInt64.self) }
	}
	func free() { base.deallocate() }
}
