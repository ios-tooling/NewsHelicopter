//
//  TerminationReason.swift
//  NewsHelicopter
//
//  Why the kernel let the process go: an `os_reason` namespace (JETSAM,
//  SIGNAL, CODESIGNING, FRONTBOARD, …) and a code within it.
//
//  The extension's `CrashReason.codes` do not carry the Mach exception's own
//  codes. Every report iOS 27.0.1 delivered had `codes[0] == 10` (EXC_CRASH,
//  whatever the exception) and the reason packed into `codes[1]` as
//  `(namespace << 32) | code` — `0xA_8BADF00D` for a watchdog kill,
//  `0x1_00000007` for a jetsam per-process-limit kill. The SDK documents the
//  codes only as "exception-specific"; the layout is read from those reports.
//

import Foundation

extension NewsHelicopterReport {
	public struct TerminationReason: Codable, Sendable, Equatable {
		/// The `os_reason` namespace (`OS_REASON_JETSAM` = 1, …) and its code.
		public let namespace: UInt32
		public let code: UInt64
		/// `JETSAM`, `FRONTBOARD`, …; an unknown namespace is its number in hex.
		public let namespaceName: String
		/// What the code means within its namespace — `per-process-limit`,
		/// `watchdog (0x8BADF00D)`, `SIGABRT` — or nil when it is not known.
		public let codeName: String?

		public init(namespace: UInt32, code: UInt64) {
			self.namespace = namespace
			self.code = code
			self.namespaceName = Self.namespaceName(namespace)
			self.codeName = Self.codeName(namespace: namespace, code: code)
		}

		/// One line: `JETSAM per-process-limit`, `FRONTBOARD watchdog (0x8BADF00D)`,
		/// `namespace 0x30 0x1234`.
		public var name: String { "\(namespaceName) \(codeName ?? Self.hex(code))" }

		/// The signal the process died of, where the reason says: a SIGNAL
		/// reason names it; jetsam, FrontBoard and RunningBoard terminate with
		/// SIGKILL (xnu's memorystatus kill and `terminate_with_reason`).
		/// Any other namespace says nothing about the signal.
		public var signalName: String? {
			switch namespace {
			case Namespace.signal: NewsHelicopterReport.signalName(Int32(truncatingIfNeeded: code))
			case Namespace.jetsam, Namespace.frontBoard, Namespace.runningBoard: "SIGKILL"
			default: nil
			}
		}

		/// The reason packed into the codes the extension is handed, or nil when
		/// they are not in that layout (or carry no reason).
		public static func decode(codes: [UInt64]) -> TerminationReason? {
			guard isCorpseLayout(codes) else { return nil }
			let packed = codes[1]
			guard packed != 0 else { return nil }
			return TerminationReason(namespace: UInt32(truncatingIfNeeded: packed >> 32), code: packed & 0xFFFF_FFFF)
		}

		/// `[EXC_CRASH, (namespace << 32) | code]`: the corpse's own wrapper
		/// first, the reason second — not the Mach exception's codes.
		public static func isCorpseLayout(_ codes: [UInt64]) -> Bool {
			codes.count >= 2 && codes[0] == UInt64(EXC_CRASH)
		}

		static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16, uppercase: true) }
	}
}
