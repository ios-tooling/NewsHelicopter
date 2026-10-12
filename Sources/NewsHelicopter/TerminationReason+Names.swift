//
//  TerminationReason+Names.swift
//  NewsHelicopter
//
//  The `os_reason` vocabulary: namespaces from xnu's `bsd/sys/reason.h`
//  (10 is xnu's OS_REASON_SPRINGBOARD, which Apple's reports call
//  FRONTBOARD), jetsam causes from `bsd/sys/kern_memorystatus.h` with the
//  names the system logs them by, FrontBoard's codes from Apple's
//  "Understanding the exception types in a crash report".
//

import Foundation

extension NewsHelicopterReport.TerminationReason {
	enum Namespace {
		static let jetsam: UInt32 = 1
		static let signal: UInt32 = 2
		static let codeSigning: UInt32 = 3
		static let frontBoard: UInt32 = 10
		static let runningBoard: UInt32 = 15
	}

	static let namespaces: [String?] = [
		"INVALID", "JETSAM", "SIGNAL", "CODESIGNING", "HANGTRACER", "TEST", "DYLD", "LIBXPC", "OBJC", "EXEC",
		"FRONTBOARD", "TCC", "REPORTCRASH", "COREANIMATION", "AGGREGATED", "RUNNINGBOARD", "SKYWALK", "SETTINGS",
		"LIBSYSTEM", "FOUNDATION", "WATCHDOG", "METAL", "WATCHKIT", "GUARD", "ANALYTICS", "SANDBOX", "SECURITY",
		"ENDPOINTSECURITY", "PAC_EXCEPTION", "BLUETOOTH_CHIP", "PORT_SPACE", "WEBKIT", "BACKLIGHTSERVICES", "MEDIA",
		"ROSETTA", "LIBIGNITION", "BOOTMOUNT", nil, "REALITYKIT", "AUDIO", "WAKEBOARD", "CORERC", "SELF_RESTRICT",
		"ARKIT", "CAMERA", "BACKBOARD", "POWEREXCEPTIONS", "SECINIT",
	]

	/// JETSAM_REASON_*, by number.
	static let jetsamCauses = [
		"invalid", "jettisoned", "highwater", "vnode-limit", "vm-pageshortage", "proc-thrashing", "fc-thrashing",
		"per-process-limit", "disk-space-shortage", "idle-exit", "zone-map-exhaustion", "vm-compressor-thrashing",
		"vm-compressor-space-shortage", "low-swap", "sustained-memory-pressure", "vm-pageout-starvation",
		"conclave-limit", "long-idle-exit",
	]

	static let frontBoardCodes: [UInt64: String] = [
		0x8BAD_F00D: "watchdog",
		0xDEAD_10CC: "deadlock: held a file or database lock while suspended",
		0xBAAD_CA11: "VoIP push without a reported call",
		0xBAD2_2222: "VoIP app resumed too often",
		0xC000_10FF: "thermal",
		0xDEAD_FA11: "force quit",
		0x2BAD_45EC: "security violation",
		0xBAAA_AAAD: "stackshot",
		0xC51B_AD01: "background task used too much CPU",
		0xC51B_AD02: "background task ran out of time",
		0xC51B_AD03: "background task ran out of time on a busy system",
	]

	/// CODESIGNING_EXIT_REASON_*, by number.
	static let codeSigningCauses = [
		1: "invalid signature", 2: "invalid page", 3: "task access port", 4: "launch constraint violation",
	]

	static func namespaceName(_ namespace: UInt32) -> String {
		guard Int(namespace) < namespaces.count, let name = namespaces[Int(namespace)] else { return "namespace \(hex(UInt64(namespace)))" }
		return name
	}

	static func codeName(namespace: UInt32, code: UInt64) -> String? {
		switch namespace {
		case Namespace.jetsam:
			if code == 100 { return "cpu-limit" }
			return code < UInt64(jetsamCauses.count) ? jetsamCauses[Int(code)] : nil
		case Namespace.signal: return NewsHelicopterReport.signalName(Int32(truncatingIfNeeded: code))
		case Namespace.codeSigning: return codeSigningCauses[Int(code)]
		case Namespace.frontBoard: return frontBoardCodes[code].map { "\($0) (\(hex(code)))" }
		default: return nil
		}
	}
}

extension NewsHelicopterReport {
	/// A signal's name from its number; nil for 0.
	public static func signalName(_ number: Int32) -> String? {
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
