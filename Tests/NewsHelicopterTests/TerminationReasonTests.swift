//
//  TerminationReasonTests.swift
//  NewsHelicopterTests
//
//  The codes real crash-extension reports carried (Crosswords build 2500,
//  iOS 27.0.1), decoded: `[10, reason]`, whatever the exception.
//

import NewsHelicopter
@testable import NewsHelicopterExtension
import Darwin
import Foundation
import Testing

@Suite("Termination reasons")
struct TerminationReasonTests {
	typealias TerminationReason = NewsHelicopterReport.TerminationReason
	static let watchdog: [UInt64] = [10, 45_293_105_165]      // 0xA_8BADF00D
	static let jetsam: [UInt64] = [10, 4_294_967_303]         // 0x1_00000007

	@Test("a watchdog kill is FrontBoard's 0x8BADF00D, delivered as SIGKILL")
	func watchdogKill() throws {
		let reason = ExceptionNames.reason(exception: EXC_CRASH, codes: Self.watchdog)
		let termination = try #require(reason.terminationReason)
		#expect(termination.namespace == 10)
		#expect(termination.code == 0x8BAD_F00D)
		#expect(termination.namespaceName == "FRONTBOARD")
		#expect(termination.name == "FRONTBOARD watchdog (0x8BADF00D)")
		#expect(reason.signalName == "SIGKILL")
		#expect(reason.resourceLimit == nil)
	}

	@Test("a jetsam kill is the per-process memory limit")
	func jetsamKill() throws {
		let reason = ExceptionNames.reason(exception: EXC_RESOURCE, codes: Self.jetsam)
		let termination = try #require(reason.terminationReason)
		#expect(termination.namespace == 1)
		#expect(termination.code == 7)
		#expect(termination.name == "JETSAM per-process-limit")
		#expect(reason.signalName == "SIGKILL", "from the reason, not from EXC_RESOURCE")
		#expect(reason.resourceLimit == nil, "the corpse layout carries no resource bits")
	}

	@Test("the other jetsam causes, SIGNAL, CODESIGNING and unknowns")
	func namespaces() {
		#expect(TerminationReason(namespace: 1, code: 2).name == "JETSAM highwater")
		#expect(TerminationReason(namespace: 1, code: 3).name == "JETSAM vnode-limit")
		#expect(TerminationReason(namespace: 1, code: 99).name == "JETSAM 0x63")
		#expect(TerminationReason(namespace: 2, code: UInt64(SIGABRT)).name == "SIGNAL SIGABRT")
		#expect(TerminationReason(namespace: 2, code: UInt64(SIGSEGV)).signalName == "SIGSEGV")
		#expect(TerminationReason(namespace: 3, code: 2).name == "CODESIGNING invalid page")
		#expect(TerminationReason(namespace: 3, code: 2).signalName == nil, "nothing decoded says which signal")
		#expect(TerminationReason(namespace: 10, code: 0xDEAD_10CC).codeName?.hasSuffix("(0xDEAD10CC)") == true)
		#expect(TerminationReason(namespace: 10, code: 0x1234).name == "FRONTBOARD 0x1234")
		#expect(TerminationReason(namespace: 0x30, code: 0x1234).name == "namespace 0x30 0x1234")
		#expect(TerminationReason(namespace: 37, code: 1).namespaceName == "namespace 0x25", "a gap in xnu's list")
	}

	@Test("codes in the Mach layout carry no termination reason")
	func machLayout() {
		#expect(TerminationReason.decode(codes: [1, 0]) == nil)
		#expect(TerminationReason.decode(codes: [UInt64(SIGABRT) << 24, 0]) == nil)
		#expect(TerminationReason.decode(codes: [10]) == nil)
		#expect(TerminationReason.decode(codes: [10, 0]) == nil)
	}

	@Test("signals come from the code that holds them")
	func signals() {
		#expect(ExceptionNames.signalName(exception: EXC_CRASH, codes: [10, 0x2_0000_0006]) == "SIGABRT", "a SIGNAL reason")
		#expect(ExceptionNames.signalName(exception: EXC_BAD_ACCESS, codes: [10, 0x2_0000_000B]) == "SIGSEGV")
		#expect(ExceptionNames.signalName(exception: EXC_BAD_ACCESS, codes: [10, 0x3_0000_0002]) == nil, "not SIGBUS from codes[0] == 10")
		#expect(ExceptionNames.signalName(exception: EXC_BREAKPOINT, codes: [10, 0x3_0000_0002]) == "SIGTRAP")
		#expect(ExceptionNames.signalName(exception: EXC_CRASH, codes: [10, 0x3_0000_0002]) == nil, "codes[0] holds no signal")
		#expect(ExceptionNames.signalName(exception: EXC_RESOURCE, codes: [0x6000_0000_0000_0000, 0]) == nil, "no SIGKILL unless decoded")
		#expect(ExceptionNames.signalName(exception: EXC_GUARD, codes: [0x2000_0000_0000_0000, 0]) == nil)
	}

	@Test("an EXC_RESOURCE in the Mach layout names its limit")
	func resourceLimit() {
		typealias Limit = NewsHelicopterReport.ResourceLimit
		#expect(Limit.decode(exception: EXC_RESOURCE, codes: [0x6400_0000_0000_0800, 0])?.name == "MEMORY HIGH_WATERMARK")
		#expect(Limit.decode(exception: EXC_RESOURCE, codes: [0x2800_0000_0000_0000, 0])?.name == "CPU CPU_MONITOR_FATAL")
		#expect(Limit.decode(exception: EXC_RESOURCE, codes: [0x4400_0000_0000_0000, 0])?.name == "WAKEUPS WAKEUPS_MONITOR")
		#expect(Limit.decode(exception: EXC_RESOURCE, codes: [0x8800_0000_0000_0000, 0])?.name == "IO LOGICAL_WRITES")
		#expect(Limit.decode(exception: EXC_RESOURCE, codes: [0xE400_0000_0000_0000, 0])?.name == "type 7 flavor 1")
		#expect(Limit.decode(exception: EXC_GUARD, codes: [0x6400_0000_0000_0000, 0]) == nil)
	}

	@Test("a binary annotation never becomes the headline; readable text still does")
	func binaryAnnotation() {
		let binary = NewsHelicopterReport.Annotation(image: "CoreUI", message: "\u{10}\u{FFFD}\u{1C}\u{1}", message2: nil, signature: nil, abortCause: 0)
		let fatal = NewsHelicopterReport.Annotation(image: "libswiftCore.dylib", message: "Fatal error: é ✓\n", message2: nil, signature: nil, abortCause: 0)
		#expect(binary.text == nil)
		#expect(fatal.text == "Fatal error: é ✓\n")
	}

	@Test("a report written before the reason was decoded still reads, and decodes on demand")
	func olderReport() throws {
		let json = #"{"exception":11,"codes":[10,4294967303],"exceptionName":"EXC_RESOURCE","signalName":"SIGKILL"}"#
		let reason = try JSONDecoder().decode(NewsHelicopterReport.Reason.self, from: Data(json.utf8))
		#expect(reason.terminationReason == nil)
		#expect(reason.termination?.name == "JETSAM per-process-limit")
		let written = try JSONEncoder().encode(ExceptionNames.reason(exception: EXC_CRASH, codes: Self.watchdog))
		#expect(try JSONDecoder().decode(NewsHelicopterReport.Reason.self, from: written).terminationReason?.code == 0x8BAD_F00D)
	}
}
