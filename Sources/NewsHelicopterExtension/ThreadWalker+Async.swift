//
//  ThreadWalker+Async.swift
//  NewsHelicopterExtension
//
//  Swift async frames. An async function's frame record points down at
//  whichever executor resumed it, not at its caller, so the plain chain goes
//  from the first async frame straight into the concurrency runtime. The
//  function marks its record — the saved fp's top nibble is 1 — and keeps
//  its async context just below it, at fp − 8. From there the logical
//  callers are the task's context chain: each context holds its parent and
//  the resume point in the parent's function. That is the walk Apple's own
//  reporter makes, and the frames it writes.
//

import Foundation

extension ThreadWalker {
	/// The top nibble of a saved fp on an async frame record (arm64, x86_64).
	static func isAsyncFrame(_ savedFP: UInt64) -> Bool {
		savedFP & 0xF000_0000_0000_0000 == 0x1000_0000_0000_0000
	}

	/// The resume points up the context chain from `context`, innermost first.
	/// A resume point is a function's entry, not a return address; every
	/// reader of a stack takes a caller's address less one, so each goes out
	/// one past the entry — which also makes them the addresses MetricKit and
	/// the system crash report give, byte for byte.
	static func asyncCallers(context: UInt64, memory: TaskMemory, limit: Int) -> [UInt64] {
		var callers: [UInt64] = []
		var seen = Set<UInt64>()
		var context = strip(context)
		while context != 0, context & 0x7 == 0, callers.count < limit, seen.insert(context).inserted,
		      let record = memory.read(context, count: 16) {
			let resume = strip(record.load(UInt64.self, at: 8))
			guard resume != 0 else { break }
			callers.append(resume + 1)
			context = strip(record.load(UInt64.self, at: 0))
		}
		return callers
	}
}
