//
//  ThreadWalker.swift
//  AutopsyExtension
//
//  Every thread of a task, with its registers and a frame-pointer walk of its
//  stack. arm64 keeps the frame chain — each frame's fp points at the saved
//  fp and lr of the caller — so a corpse's stacks can be read without unwind
//  tables: read two words, step, repeat. Apple's crash reporter does the same
//  when it has nothing better.
//

import Darwin
import Foundation

public struct ThreadSnapshot: Sendable {
	public let id: UInt64
	public let name: String?
	/// pc, lr, sp, fp — and far, esr, exception from the exception state.
	public let registers: [String: UInt64]
	/// Return addresses, innermost first: the pc, then each caller.
	public let frames: [UInt64]
	/// The kernel recorded a fault on this thread — the one that crashed, when
	/// the crash was a fault rather than a signal.
	public var faulted: Bool { (registers["exception"] ?? 0) != 0 }
}

public enum ThreadWalker {
	public static let defaultFrameLimit = 256
	public static let defaultThreadLimit = 256

	/// Snapshot every thread of `memory.task`. Thread ports are given back to
	/// the kernel before returning.
	public static func threads(of memory: TaskMemory, frameLimit: Int = defaultFrameLimit, threadLimit: Int = defaultThreadLimit) -> [ThreadSnapshot] {
		var list: thread_act_array_t?
		var count: mach_msg_type_number_t = 0
		guard task_threads(memory.task, &list, &count) == KERN_SUCCESS, let list else { return [] }
		defer {
			for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[index]) }
			vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_act_t>.size))
		}
		return (0..<min(Int(count), threadLimit)).map { snapshot(of: list[$0], memory: memory, frameLimit: frameLimit) }
	}

	static func snapshot(of thread: thread_act_t, memory: TaskMemory, frameLimit: Int) -> ThreadSnapshot {
		var registers: [String: UInt64] = [:]
		var frames: [UInt64] = []
		#if arch(arm64)
			var state = arm_thread_state64_t()
			var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
			let got = withUnsafeMutablePointer(to: &state) { pointer in
				pointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
					thread_get_state(thread, ARM_THREAD_STATE64, $0, &stateCount)
				}
			}
			if got == KERN_SUCCESS {
				let pc = strip(state.__pc), lr = strip(state.__lr), fp = strip(state.__fp), sp = strip(state.__sp)
				registers = ["pc": pc, "lr": lr, "fp": fp, "sp": sp]
				frames = walk(pc: pc, lr: lr, fp: fp, memory: memory, limit: frameLimit)
			}
			var exception = arm_exception_state64_t()
			var exceptionCount = mach_msg_type_number_t(MemoryLayout<arm_exception_state64_t>.size / MemoryLayout<natural_t>.size)
			let gotException = withUnsafeMutablePointer(to: &exception) { pointer in
				pointer.withMemoryRebound(to: natural_t.self, capacity: Int(exceptionCount)) {
					thread_get_state(thread, ARM_EXCEPTION_STATE64, $0, &exceptionCount)
				}
			}
			if gotException == KERN_SUCCESS {
				registers["far"] = exception.__far
				registers["esr"] = UInt64(exception.__esr)
				registers["exception"] = UInt64(exception.__exception)
			}
		#endif
		return ThreadSnapshot(id: identifier(of: thread), name: name(of: thread), registers: registers, frames: frames)
	}

	/// pc first; then the callers off the frame chain. The link register is
	/// the caller of a leaf that has not saved it yet, so it goes second
	/// unless the chain already starts with it.
	static func walk(pc: UInt64, lr: UInt64, fp: UInt64, memory: TaskMemory, limit: Int) -> [UInt64] {
		var frames = [pc]
		var chain: [UInt64] = []
		var frame = fp
		var previous: UInt64 = 0
		while frame != 0, frame & 0xF == 0, frame > previous, chain.count < limit,
		      let saved = memory.read(frame, count: 16) {
			let savedFP = strip(saved.load(UInt64.self, at: 0))
			let returnAddress = strip(saved.load(UInt64.self, at: 8))
			guard returnAddress != 0 else { break }
			chain.append(returnAddress)
			previous = frame
			frame = savedFP
		}
		if lr != 0, chain.first != lr { frames.append(lr) }
		frames.append(contentsOf: chain)
		return Array(frames.prefix(limit))
	}

	/// Pointer authentication keeps its signature in the top bits; an address
	/// to symbolicate wants only the 47 a user-space address can use.
	public static func strip(_ value: UInt64) -> UInt64 { value & 0x0000_7FFF_FFFF_FFFF }

	static func identifier(of thread: thread_act_t) -> UInt64 {
		var info = thread_identifier_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
		let result = withUnsafeMutablePointer(to: &info) { pointer in
			pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
				thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &count)
			}
		}
		return result == KERN_SUCCESS ? info.thread_id : 0
	}

	static func name(of thread: thread_act_t) -> String? {
		var info = thread_extended_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size)
		let result = withUnsafeMutablePointer(to: &info) { pointer in
			pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
				thread_info(thread, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &count)
			}
		}
		guard result == KERN_SUCCESS else { return nil }
		let name = withUnsafePointer(to: &info.pth_name) { pointer in
			pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXTHREADNAMESIZE)) { String(cString: $0) }
		}
		return name.isEmpty ? nil : name
	}
}
