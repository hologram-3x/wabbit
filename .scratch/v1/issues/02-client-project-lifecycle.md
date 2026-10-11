# 02: Client and Project lifecycle

**What to build:** The freelancer can rename Clients and Projects, Close a Project when the work ends and Reopen it later, and record each Client's email domains. Closed Projects stay in the archive but can't receive time.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] Rename, Close and Reopen work for Clients and Projects
- [x] A Client always has at least one Project (removing or closing the last one is handled as defined in the spec)
- [x] Closed Projects reject new Sessions, both started and Manual
- [x] Closed Projects are hidden from the tray and from prompts, but still appear in the Overview
- [x] Email domains can be added to and removed from a Client
- [x] Lifecycle rules are covered by tests at the core seam

## Resolution notes

Core: `Sources/HoursCore/Lifecycle.swift` (migration `v2-lifecycle`), tests in `Tests/HoursCoreTests/LifecycleTests.swift` (13 tests total pass; `scripts/build-app.sh` builds).

Defaults chosen (spec silent):
- The last Open Project of a Client cannot be removed or Closed (`HoursError.lastProject`). Closing a whole Client is allowed and archives all its Projects; Reopening the Client restores them.
- Closing a Project/Client stops its running Session at that instant.
- Single rule for ticket 04: `Tracker.requireOpen(projectId:)` (throws `.projectClosed`); `start` already uses it. Manual Sessions untested until 04 exists, so the "Manual" half of box 3 is covered only by that shared check.
- Overview does not exist yet (05): `closedProjects()` / `projects()` still list Closed ones; `openProjects()` feeds tray/prompts.
- Email domains are lowercased, a leading `@` is stripped, duplicates ignored.

Needs a human click-through: tray "Manage Clients…" window (rename on Return, Close/Reopen, add Project, add/remove email domain), Closed Projects disappearing from the tray, window coming to front from the accessory (no-Dock) app. UI is not unit tested.
