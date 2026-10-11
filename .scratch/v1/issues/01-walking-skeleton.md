# 01: Walking skeleton: track one Project from the menu bar

**What to build:** A freelancer installs a signed Hours app that lives only in the menu bar, creates a Client with its first Project, and starts and stops a Session from the tray. The Session is still there after quitting and relaunching. This also sets up the core package with its test seam (fake clock, fake detection feed, real in-memory SQLite) so every later ticket tests through it.

**Blocked by:** None (can start immediately)

**Status:** resolved (remaining: human click-through and release secrets, see Comments)

- [ ] The app shows a tray icon and no Dock icon, and launches at login
- [ ] CI builds a signed, notarized DMG
- [x] Creating a Client requires creating its first Project
- [ ] Start and Stop from the tray create one Session with exact start and end instants
- [x] A running Session survives an app restart
- [x] The core reads time only from an injected clock; a core test advances the fake clock and checks the Session's duration
- [x] Storage uses SQLite with versioned migrations

## Comments

**Agent (implementation, branch `feat/01-walking-skeleton`):** layout and decisions in [ADR 0002](../../../docs/adr/0002-swiftpm-app-bundle.md); build commands in README.

Verified:
- `swift test`: 6 tests pass (Client needs a named first Project; Start/Stop exact instants and duration with the fake clock; starting again stops the running Session at the same instant; running Session survives reopening the database file; detection events through the fake feed change nothing yet).
- `scripts/build-app.sh dmg` builds an ad-hoc signed `build/Hours.app` and `build/Hours.dmg`. Launched with `open`: the process runs as `type="UIElement"` (no Dock icon), exposes one status-menu item, and the clock icon shows in the menu bar; migration `v1` was applied to `~/Library/Application Support/Hours/hours.sqlite`.
- Restart, in the real app: with a running Session seeded into the database, relaunching shows the Stop icon.
- The Client creation API takes the first Project as a required argument and rejects empty names, so a Client cannot exist without one.

Needs a human (ready-for-human):
- **Tray click-through:** open the tray, create a Client + first Project, Start, Stop; check the Session row has exact start/end (`sqlite3 ~/Library/Application\ Support/Hours/hours.sqlite 'select * from session'`). Then the "tray icon / no Dock icon" box can be ticked together with launch at login.
- **Launch at login:** copy `Hours.app` to `/Applications` and run it once (it registers itself on that first run; the tray toggle also works), log out and in, check Hours is running.
- **Signed, notarized DMG:** add the secrets listed in `docs/release.md`, push a `v*` tag, check the `release` job's DMG passes `spctl`.
