// swift-tools-version: 6.2

import PackageDescription

// Autopsy: crash reporting built on Apple's CrashReportExtension (iOS 27 /
// macOS 27). The crashed app leaves breadcrumbs in a Mach-O section
// (AutopsyCrumbs, C, linked into the app), the extension reads the corpse —
// threads, stacks, crash annotations, those breadcrumbs — and writes an
// AutopsyReport into the app group for the app to send however it sends
// things. Autopsy holds the report model and the app-side API; the engine in
// AutopsyExtension needs no CrashReportExtension until its last step, so it
// builds and tests on any host by reading the current task.
let package = Package(
	name: "Autopsy",
	platforms: [.macOS(.v15), .iOS(.v18)],
	products: [
		.library(name: "Autopsy", targets: ["Autopsy"]),
		.library(name: "AutopsyExtension", targets: ["AutopsyExtension"]),
	],
	targets: [
		.target(name: "AutopsyCrumbs"),
		.target(name: "Autopsy", dependencies: ["AutopsyCrumbs"]),
		.target(name: "AutopsyExtension", dependencies: ["Autopsy", "AutopsyCrumbs"]),
		.testTarget(name: "AutopsyTests", dependencies: ["Autopsy", "AutopsyExtension", "AutopsyCrumbs"]),
	]
)
