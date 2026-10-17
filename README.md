---
status: v1.0
---

<p align="center">🐇</p>

# Wabbit

Named after the White Rabbit from *Alice in Wonderland*.

A native macOS menu-bar time tracker for freelancers. It helps you keep track of how much time you spent on each project for your clients: always active on you mac, it can prompt you to start tracking automatically when a call start or when a certain app is opened, so you won't forget to track anything. 

## Why?

I don't know about you, but I constantly forget to keep trak of the time I spend working for clients. I tried to use an excel sheet, which worked pretty well but sometimes I forgot to open it, sometimes I forgot to write down the time I stopped working, or when I got back… I tried some other tools as well but the outcome was similar. This way I always have a quick way to track my time. 

## How it works:
It prompts you to start tracking when a call begins or you open a work app, tracks Sessions per Client and Project, and shows whether a Client is underbilled by comparing tracked time with what was agreed. Exports precise or rounded time recordings as a CSV that can be filtered per client, project or date.

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
open build/Wabbit.app          # tray icon only, no Dock icon
scripts/build-app.sh dmg       # also build/Wabbit.dmg
```

Layout: one SwiftPM package. `Sources/WabbitCore` (domain and storage, no Apple-only imports), `Sources/Wabbit` (the menu-bar app), `Tests/WabbitCoreTests`, `App/Info.plist`. See [ADR 0002](./docs/adr/0002-swiftpm-app-bundle.md). Data lives in `~/Library/Application Support/Wabbit/hours.sqlite`. Signed and notarized releases: [docs/release.md](./docs/release.md).

## License

GPL-3.0, see [LICENSE](./LICENSE).
