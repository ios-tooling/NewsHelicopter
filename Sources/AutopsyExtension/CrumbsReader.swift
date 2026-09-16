//
//  CrumbsReader.swift
//  AutopsyExtension
//
//  The app's breadcrumb block, read out of its executable in the corpse by
//  section name — `__DATA,__autopsy` — and decoded by the layout the app-side
//  library shares.
//

import Autopsy
import Foundation

public enum CrumbsReader {
	/// The crumbs in the executable at `baseAddress`, or nil when it carries
	/// no block (or one from a different layout).
	public static func read(executableAt baseAddress: UInt64, memory: TaskMemory) -> AutopsyReport.Crumbs? {
		MachOImage(memory: memory, baseAddress: baseAddress).flatMap(read(image:))
	}

	/// The crumbs in an already-parsed image, or nil when it carries none.
	public static func read(image: MachOImage) -> AutopsyReport.Crumbs? {
		guard let section = image.section(AutopsyCrumbsLayout.section, in: AutopsyCrumbsLayout.segment),
		      section.size >= UInt64(AutopsyCrumbsLayout.size),
		      let data = image.memory.read(section.address, count: AutopsyCrumbsLayout.size) else { return nil }
		return AutopsyCrumbsLayout.decode(data)
	}
}
