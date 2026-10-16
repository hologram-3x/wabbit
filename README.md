---
status: in-progress
---

<h1 align="center">🐇</h1>

# Wabbit

Named after the White Rabbit, "W. Rabbit" on his door in Alice in Wonderland.

A native macOS menu-bar time tracker for freelancers. It prompts you to start tracking when a call begins or you open a work app, tracks Sessions per Client and Project, and shows whether a Client is underbilled by comparing tracked time with what was agreed. Exports precise or rounded CSV.

- [CONTEXT.md](./CONTEXT.md): domain vocabulary
- [PLAN.md](./PLAN.md): v1 plan
- [docs/adr/](./docs/adr/): decisions
- [.scratch/v1/spec.md](./.scratch/v1/spec.md): v1 spec
- [.scratch/v1/issues/](./.scratch/v1/issues/): v1 tickets

## Build and run

Requires Xcode 16+ (Swift 6), macOS 14+.

```sh
swift test                     # WabbitCore tests (fake clock, fake detection feed, in-memory SQLite)
scripts/build-app.sh           # build/Wabbit.app, ad-hoc signed
open build/Wabbit.app           # tray icon only, no Dock icon
scripts/build-app.sh dmg       # also build/Wabbit.dmg
```

Layout: one SwiftPM package. `Sources/WabbitCore` (domain and storage, no Apple-only imports), `Sources/Wabbit` (the menu-bar app), `Tests/WabbitCoreTests`, `App/Info.plist`. See [ADR 0002](./docs/adr/0002-swiftpm-app-bundle.md). Data lives in `~/Library/Application Support/Wabbit/hours.sqlite`. Signed and notarized releases: [docs/release.md](./docs/release.md).
