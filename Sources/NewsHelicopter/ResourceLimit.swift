//
//  ResourceLimit.swift
//  NewsHelicopter
//
//  Which limit an EXC_RESOURCE was for, from the exception's own first code
//  (`<kern/exc_resource.h>`: the type in bits 61–63, the flavor in 58–60).
//  Only codes in the Mach layout carry it; the extension's corpse layout
//  (`[EXC_CRASH, reason]`) does not, and decodes to nil.
//

import Foundation

extension NewsHelicopterReport {
	public struct ResourceLimit: Codable, Sendable, Equatable {
		/// RESOURCE_TYPE_* (CPU = 1, WAKEUPS, MEMORY, IO, THREADS, PORTS) and its flavor.
		public let type: Int
		public let flavor: Int
		/// `MEMORY HIGH_WATERMARK`, `CPU CPU_MONITOR_FATAL`, …
		public let name: String

		public init(type: Int, flavor: Int) {
			self.type = type
			self.flavor = flavor
			let names = Self.names[type]
			let flavorName = names.flatMap { (1..<$0.flavors.count).contains(flavor) ? $0.flavors[flavor] : nil } ?? "flavor \(flavor)"
			self.name = "\(names?.type ?? "type \(type)") \(flavorName)"
		}

		public static func decode(exception: Int32, codes: [UInt64]) -> ResourceLimit? {
			guard exception == EXC_RESOURCE, let code = codes.first else { return nil }
			let type = Int((code >> 61) & 0x7), flavor = Int((code >> 58) & 0x7)
			guard type != 0 else { return nil }
			return ResourceLimit(type: type, flavor: flavor)
		}

		/// Flavors by number, index 0 unused.
		static let names: [Int: (type: String, flavors: [String])] = [
			1: ("CPU", ["", "CPU_MONITOR", "CPU_MONITOR_FATAL"]),
			2: ("WAKEUPS", ["", "WAKEUPS_MONITOR"]),
			3: ("MEMORY", ["", "HIGH_WATERMARK", "DIAG_MEMLIMIT", "CONCLAVE_LIMIT"]),
			4: ("IO", ["", "PHYSICAL_WRITES", "LOGICAL_WRITES"]),
			5: ("THREADS", ["", "HIGH_WATERMARK"]),
			6: ("PORTS", ["", "PORT_SPACE_FULL"]),
		]
	}
}
