//
//  NewsHelicopterReportBuilder+Images.swift
//  NewsHelicopterExtension
//
//  Which image an address falls in, and the short list of images a report
//  carries.
//

import NewsHelicopter
import Foundation

extension NewsHelicopterReportBuilder {
	func frame(at address: UInt64, in images: [Image], located: Int?, table: ImageTable,
	           symbols: [UInt64: [NewsHelicopterReport.Symbol]]) -> NewsHelicopterReport.Frame {
		NewsHelicopterReport.Frame(address: address, imageIndex: located.map { table.index(of: $0) },
		                           offsetInImage: located.map { address - images[$0].baseAddress }, symbols: symbols[address] ?? [])
	}

	/// The image an address belongs to, as an index into `images` (sorted by
	/// base): the one with the greatest base at or below it, if its range
	/// reaches. Ranges overlap in the shared cache — a dylib's span runs from
	/// its text to its linkedit, across other dylibs' text — so the nearest
	/// base is the rule, not the first range that contains the address.
	func locate(_ address: UInt64, in images: [Image]) -> Int? {
		var low = 0, high = images.count - 1, nearest: Int?
		while low <= high {
			let middle = (low + high) / 2
			if images[middle].baseAddress <= address { nearest = middle; low = middle + 1 } else { high = middle - 1 }
		}
		guard let nearest, address < images[nearest].baseAddress + images[nearest].size else { return nil }
		return nearest
	}

	/// The frames a thread reports: the walk's, less a link-register guess
	/// that symbols show to be inside the crashing function itself.
	func frames(of snapshot: ThreadSnapshot, symbols: [UInt64: [NewsHelicopterReport.Symbol]]) -> [UInt64] {
		guard snapshot.secondFrameIsLinkRegister, snapshot.frames.count > 1,
		      let first = symbols[snapshot.frames[0]]?.last?.name, symbols[snapshot.frames[1]]?.last?.name == first else { return snapshot.frames }
		var frames = snapshot.frames
		frames.remove(at: 1)
		return frames
	}

	/// The images the report carries: a subset of the sorted list, renumbered
	/// from zero in the same order.
	struct ImageTable {
		let sortedIndices: [Int]
		private let position: [Int: Int]
		init(indices: Set<Int>) {
			sortedIndices = indices.sorted()
			position = Dictionary(uniqueKeysWithValues: sortedIndices.enumerated().map { ($1, $0) })
		}
		func index(of sortedIndex: Int) -> Int { position[sortedIndex]! }
	}
}
