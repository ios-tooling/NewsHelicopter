# News Helicopter

Crash reporting on Apple's `CrashReportExtension` (iOS 27, iPadOS 27, macOS 27).
When an app crashes, the system runs its crash-reporter extension out of
process with a read-only port to the corpse. News Helicopter is what the extension
does with it, and what the app leaves for it to find.

- **NewsHelicopterCrumbs** (C) — a fixed block in the app's `__DATA,__helicopter`
  section: a run id, the current screen, and a ring of the last 24 lines.
  The extension finds it by section name, so a stripped build is fine.
- **NewsHelicopter** — the app-side API (`NewsHelicopterCrumbs.beginRun()`, `.setScreen`,
  `.note`), the `NewsHelicopterReport` model, and `NewsHelicopterReportStore`, a directory
  of one-JSON-file-per-report — an app group's, so the extension writes and
  the app reads.
- **NewsHelicopterExtension** — the engine: cross-task memory reads, a Mach-O
  section finder, an arm64 frame-pointer walk of every thread, the
  `__crash_info` annotations (the Swift fatal error text, an abort message,
  dyld's complaint), the crumbs, and on-device symbolication. Only its last
  step, `NewsHelicopterReporter`, needs Apple's framework; the rest reads any task,
  which is how the tests exercise it against their own process.

## The extension

```swift
import NewsHelicopterExtension
import CrashReportExtension

@main
struct MyCrashReporter: CrashReporterExtension {
	func processCrashReport(process: CrashedProcess) {
		guard let store = NewsHelicopterReportStore(appGroup: "group.example.app", path: "CrashReports") else { return }
		NewsHelicopterReporter(store: store).process(process)
	}
}
```

The extension target is an ExtensionKit extension — Xcode's Crash Reporter
Extension template, or by hand: product type
`com.apple.product-type.extensionkit-extension`, embedded by an "Embed
ExtensionKit Extensions" phase into the app's `Extensions/` folder (not
`PlugIns/`, where installd expects an `NSExtension` dictionary and refuses
the app) — with a child bundle id (`com.example.app.crash-reporter`),
`EXAppExtensionAttributes/EXExtensionPointIdentifier =
com.apple.crash-reporter.extension` in its Info.plist, the same App Group as
the app, and deployment targets of iOS 27 / macOS 27 (the app's can stay
lower; an older system ignores the extension). The framework is not in the
simulator SDK, so guard the entry point with `#if canImport(CrashReportExtension)`
and give the simulator a `@main` that does nothing.

Nothing in the extension talks to the network: its lifetime is short and
undocumented. It writes the report and returns; the app sends it next launch.

The extension runs under a **6 MB** jetsam limit, and a corpse maps some
1,450 images whose load commands together outweigh that — so the engine
parses each image once and lets it go, and the report carries only the
images frames land in. A real crash on an iPhone 15 Pro Max took ~320 ms at
a ~3 MB footprint; every report records both (`elapsedMilliseconds`,
`memoryFootprintBytes`), so the budget is measured, not guessed.

## The app

```swift
NewsHelicopterCrumbs.beginRun()                 // once, at launch
NewsHelicopterCrumbs.setScreen("Library")       // as the reader moves
NewsHelicopterCrumbs.note("sync started")       // as things happen

for report in store.reports() {          // next launch
	send(report); store.remove(report)
}
```

`NewsHelicopterReport` carries the Mach reason (and its signal), every image with
its UUID, every thread with registers and frames (address, image, offset,
and whatever the device symbolicated), the annotations, the crumbs, and how
long the extension took — so its budget can be learned rather than guessed.

Not covered, by design: hangs, watchdog kills and jetsam are not Mach
exceptions and never reach a crash extension. Keep MetricKit for those.
