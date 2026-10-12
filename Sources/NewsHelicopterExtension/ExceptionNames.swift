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

	/// The reason with everything the codes say decoded: the signal, the
	/// termination reason, an EXC_RESOURCE's limit.
	public static func reason(exception: Int32, codes: [UInt64]) -> NewsHelicopterReport.Reason {
		NewsHelicopterReport.Reason(exception: exception, codes: codes, exceptionName: name(exception),
		                            signalName: signalName(exception: exception, codes: codes),
		                            terminationReason: .decode(codes: codes),
		                            resourceLimit: .decode(exception: exception, codes: codes))
	}

	/// The signal the process died of. A termination reason that names one
	/// wins; otherwise the signal a Mach exception is delivered as — SIGSEGV
	/// for a bad access, SIGTRAP for the `brk` a Swift trap executes — read
	/// from the Mach codes only when the codes are those (not the extension's
	/// `[EXC_CRASH, reason]`). EXC_RESOURCE and EXC_GUARD name no signal of
	/// their own: a kill is only reported as SIGKILL when the reason says so.
	public static func signalName(exception: Int32, codes: [UInt64]) -> String? {
		let termination = NewsHelicopterReport.TerminationReason.decode(codes: codes)
		if let signal = termination?.signalName { return signal }
		let machCodes = !NewsHelicopterReport.TerminationReason.isCorpseLayout(codes)
		switch exception {
		case EXC_BAD_ACCESS where machCodes && !codes.isEmpty: return codes[0] == UInt64(KERN_INVALID_ADDRESS) ? "SIGSEGV" : "SIGBUS"
		case EXC_BAD_INSTRUCTION: return "SIGILL"
		case EXC_ARITHMETIC: return "SIGFPE"
		case EXC_BREAKPOINT: return "SIGTRAP"
		case EXC_SOFTWARE where machCodes && codes.first == 0x10003 && codes.count > 1: return signal(Int32(truncatingIfNeeded: codes[1]))
		case EXC_CRASH where machCodes && !codes.isEmpty: return signal(Int32((codes[0] >> 24) & 0xFF))
		default: return nil
		}
	}

	static func signal(_ number: Int32) -> String? { NewsHelicopterReport.signalName(number) }
}
