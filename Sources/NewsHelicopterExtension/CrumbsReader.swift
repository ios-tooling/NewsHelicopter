//
//  CrumbsReader.swift
//  NewsHelicopterExtension
//
//  The app's breadcrumb block, read out of its executable in the corpse by
//  section name — `__DATA,__helicopter` — and decoded by the layout the app-side
//  library shares.
//

import NewsHelicopter
import Foundation

public enum CrumbsReader {
	/// The crumbs in the executable at `baseAddress`, or nil when it carries
	/// no block (or one from a different layout).
	public static func read(executableAt baseAddress: UInt64, memory: TaskMemory) -> NewsHelicopterReport.Crumbs? {
		MachOImage(memory: memory, baseAddress: baseAddress).flatMap(read(image:))
	}

	/// The crumbs in an already-parsed image, or nil when it carries none.
	public static func read(image: MachOImage) -> NewsHelicopterReport.Crumbs? {
		guard let section = image.section(NewsHelicopterCrumbsLayout.section, in: NewsHelicopterCrumbsLayout.segment),
		      section.size >= UInt64(NewsHelicopterCrumbsLayout.size),
		      let data = image.memory.read(section.address, count: NewsHelicopterCrumbsLayout.size) else { return nil }
		return NewsHelicopterCrumbsLayout.decode(data)
	}
}
