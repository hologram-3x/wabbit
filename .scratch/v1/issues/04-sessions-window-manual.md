# 04: Sessions window and Manual Sessions

**What to build:** The freelancer opens a window listing Sessions per Project or per day and can add a forgotten Session, or edit or delete an existing one. Hand-added Sessions are marked Manual.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] Sessions are listed per Project and per day
- [x] Add, edit and delete Sessions; added Sessions are marked Manual
- [x] Adding or editing a Session that overlaps another is rejected, and the error names the conflicting Session
- [x] A Session crossing midnight belongs to the day it started
- [ ] Adding a 2-hour Session for yesterday takes a few seconds
- [x] Overlap and Manual rules are covered by core tests

## Notes

- Core: `Sources/HoursCore/ManualSessions.swift` (migration `v4-manual` adds `session.manual`); `addManualSession`, `editSession`, `deleteSession`, `sessions(onDay:)`, `allSessions`. Reuses `requireOpen` for Closed Projects (add, and edit into a Closed Project).
- Defaults: touching edges are not an overlap; a running Session counts as ending now; the running Session cannot be edited or deleted (stop it first); end <= start is `invalidRange` in the core, but the add form treats an earlier end time as next-day (midnight crossing, stays on the start day); editing keeps the Manual flag.
- Needs a human click-through (UI not exercised): open "Sessions..." from the tray, add yesterday 09:00-11:00 (the form defaults to this; "a few seconds" box left unticked), check the Manual badge, day/Project grouping, the overlap error text, Edit sheet and Delete.
