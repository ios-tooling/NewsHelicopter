// swift-tools-version: 6.2

import PackageDescription

// News Helicopter: crash reporting built on Apple's CrashReportExtension (iOS 27 /
// macOS 27). The crashed app leaves breadcrumbs in a Mach-O section
// (NewsHelicopterCrumbs, C, linked into the app), the extension reads the corpse —
// threads, stacks, crash annotations, those breadcrumbs — and writes a
// NewsHelicopterReport into the app group for the app to send however it sends
// things. NewsHelicopter holds the report model and the app-side API; the engine in
// NewsHelicopterExtension needs no CrashReportExtension until its last step, so it
// builds and tests on any host by reading the current task.
let package = Package(
	name: "NewsHelicopter",
	platforms: [.macOS(.v15), .iOS(.v18)],
	products: [
		.library(name: "NewsHelicopter", targets: ["NewsHelicopter"]),
		.library(name: "NewsHelicopterExtension", targets: ["NewsHelicopterExtension"]),
	],
	targets: [
		.target(name: "NewsHelicopterCrumbs"),
		.target(name: "NewsHelicopter", dependencies: ["NewsHelicopterCrumbs"]),
		.target(name: "NewsHelicopterExtension", dependencies: ["NewsHelicopter", "NewsHelicopterCrumbs"]),
		.testTarget(name: "NewsHelicopterTests", dependencies: ["NewsHelicopter", "NewsHelicopterExtension", "NewsHelicopterCrumbs"]),
	]
)
