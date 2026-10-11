# 03: Quick Start and tray state

**What to build:** The tray lists the most-used Open Projects for one-click Quick Start, plus an "Other…" entry. While a Session runs, the icon becomes Stop and the tray shows the running Project and its live duration.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] Quick Start shows the top N Open Projects by recent use, plus "Other…"
- [x] Starting a Session while one runs stops the running one at the same instant (one Session at a time)
- [x] While a Session runs, the tray icon is Stop and shows the Project name and live duration
- [x] The tray state is correct after sleep and wake
- [x] The one-Session rule and Quick Start ordering are covered by core tests

## Notes

- "Recent use" = latest Session start per Project (manual and running count); ties and never-used Projects order by name, then id. `Tracker.quickStartProjects(limit:)` in `QuickStart.swift`; N = 5.
- "Other…" is a submenu with the remaining Open Projects.
- Tray label while running: Stop icon + Project name + `1h05`-style duration, refreshed by a 60 s timer that exists only while a Session runs. The open popover uses `Text(style: .timer)` for second-level precision.
- `NSWorkspace.didWakeNotification` re-reads the DB and the clock.
- Needs a human click-through: label rendering in the real menu bar, the "Other…" submenu inside the `.window` popover, sleep/wake with a running Session. Tray code is not unit-tested (core tests cover ordering and the one-Session rule).
