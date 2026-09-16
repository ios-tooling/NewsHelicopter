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

	/// The image whose range holds the address, as an index into `images`
	/// (sorted by base), or nil for an address no image maps.
	func locate(_ address: UInt64, in images: [Image]) -> Int? {
		var low = 0, high = images.count - 1
		while low <= high {
			let middle = (low + high) / 2
			let image = images[middle]
			if address < image.baseAddress { high = middle - 1 }
			else if address >= image.baseAddress + image.size { low = middle + 1 }
			else { return middle }
		}
		return nil
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
