# One SwiftPM package, app bundled by a script

Wabbit is a single Swift package: the `WabbitCore` library (domain + GRDB storage, no Apple-only imports), the `Wabbit` executable (SwiftUI `MenuBarExtra` shell) and `WabbitCoreTests`. `scripts/build-app.sh` wraps the executable into `Wabbit.app` with `App/Info.plist` (`LSUIElement` = no Dock icon), signs it and optionally packs a DMG. There is no `.xcodeproj`: everything builds with `swift build` / `swift test`, locally and in CI, and the package still opens in Xcode.

## Considered Options

- **Checked-in Xcode project**: hand-edited `project.pbxproj` merges badly and can't be generated reproducibly without extra tools.
- **XcodeGen / Tuist**: reproducible, but another tool to install and keep in step for an app with one target and no assets yet.

## Consequences

- Things an Xcode app target gives for free are done by hand in the script: Info.plist, resource bundles copied into `Contents/Resources`, signing. If the app grows entitlements, an asset catalog or a Sparkle framework that the script can't handle cleanly (ticket 13), switch to XcodeGen then.
- The core opens storage from a file path (`nil` = in-memory), so the app never imports GRDB.
- Time comes from an injected `WallClock`; detection reaches the core through a `DetectionFeed` emitting `DetectionEvent`s. Tests use a fake clock, a fake feed and real in-memory SQLite.
- Launch at login (`SMAppService.mainApp`) is registered automatically only the first time the app runs from `/Applications`, so dev builds never add themselves as login items; a tray toggle turns it on or off.
- Bundle identifier: `org.opencom-italy.wabbit`.
