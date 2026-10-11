---
status: in-progress
---

# Hours (working name)

A native macOS menu-bar time tracker for freelancers. It prompts you to start tracking when a call begins or you open a work app, tracks Sessions per Client and Project, and shows whether a Client is underbilled by comparing tracked time with what was agreed. Exports precise or rounded CSV.

- [CONTEXT.md](./CONTEXT.md): domain vocabulary
- [PLAN.md](./PLAN.md): v1 plan
- [docs/adr/](./docs/adr/): decisions
- [.scratch/v1/spec.md](./.scratch/v1/spec.md): v1 spec
- [.scratch/v1/issues/](./.scratch/v1/issues/): v1 tickets

## Build and run

Requires Xcode 16+ (Swift 6), macOS 14+.

```sh
swift test                     # HoursCore tests (fake clock, fake detection feed, in-memory SQLite)
scripts/build-app.sh           # build/Hours.app, ad-hoc signed
open build/Hours.app           # tray icon only, no Dock icon
scripts/build-app.sh dmg       # also build/Hours.dmg
```

Layout: one SwiftPM package. `Sources/HoursCore` (domain and storage, no Apple-only imports), `Sources/Hours` (the menu-bar app), `Tests/HoursCoreTests`, `App/Info.plist`. See [ADR 0002](./docs/adr/0002-swiftpm-app-bundle.md). Data lives in `~/Library/Application Support/Hours/hours.sqlite`. Signed and notarized releases: [docs/release.md](./docs/release.md).
