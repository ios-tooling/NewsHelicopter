//
//  ExceptionNames.swift
//  NewsHelicopterExtension
//
//  The Mach exception vocabulary, and the signal each would have become.
//

import Darwin
import Foundation

public enum ExceptionNames {
	public static func name(_ exception: Int32) -> String {
		switch exception {
		case EXC_BAD_ACCESS: "EXC_BAD_ACCESS"
		case EXC_BAD_INSTRUCTION: "EXC_BAD_INSTRUCTION"
		case EXC_ARITHMETIC: "EXC_ARITHMETIC"
		case EXC_EMULATION: "EXC_EMULATION"
		case EXC_SOFTWARE: "EXC_SOFTWARE"
		case EXC_BREAKPOINT: "EXC_BREAKPOINT"
		case EXC_SYSCALL: "EXC_SYSCALL"
		case EXC_MACH_SYSCALL: "EXC_MACH_SYSCALL"
		case EXC_RPC_ALERT: "EXC_RPC_ALERT"
		case EXC_CRASH: "EXC_CRASH"
		case EXC_RESOURCE: "EXC_RESOURCE"
		case EXC_GUARD: "EXC_GUARD"
		case EXC_CORPSE_NOTIFY: "EXC_CORPSE_NOTIFY"
		default: "EXC_\(exception)"
		}
	}

	/// The signal a Mach exception is delivered as — SIGSEGV for a bad
	/// access, SIGTRAP for the `brk` a Swift trap executes. EXC_CRASH and a
	/// soft-signal EXC_SOFTWARE carry the signal in their codes.
	public static func signalName(exception: Int32, codes: [UInt64]) -> String? {
		switch exception {
		case EXC_BAD_ACCESS: return codes.first == UInt64(KERN_INVALID_ADDRESS) ? "SIGSEGV" : "SIGBUS"
		case EXC_BAD_INSTRUCTION: return "SIGILL"
		case EXC_ARITHMETIC: return "SIGFPE"
		case EXC_BREAKPOINT: return "SIGTRAP"
		case EXC_SOFTWARE where codes.first == 0x10003 && codes.count > 1: return signal(Int32(truncatingIfNeeded: codes[1]))
		case EXC_CRASH where !codes.isEmpty: return signal(Int32((codes[0] >> 24) & 0xFF))
		case EXC_GUARD: return "SIGKILL"
		case EXC_RESOURCE: return "SIGKILL"
		default: return nil
		}
	}

	static func signal(_ number: Int32) -> String? {
		switch number {
		case SIGABRT: "SIGABRT"
		case SIGBUS: "SIGBUS"
		case SIGFPE: "SIGFPE"
		case SIGILL: "SIGILL"
		case SIGKILL: "SIGKILL"
		case SIGSEGV: "SIGSEGV"
		case SIGTRAP: "SIGTRAP"
		case SIGTERM: "SIGTERM"
		case SIGSYS: "SIGSYS"
		case SIGPIPE: "SIGPIPE"
		case 0: nil
		default: "SIG\(number)"
		}
	}
}
