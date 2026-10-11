# 10: Watched Apps with default Projects

**What to build:** The freelancer marks apps as Watched Apps (e.g. VS Code, Photoshop), each with an optional default Project. Using one prompts them to start tracking.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] Pick Watched Apps from installed apps, each with an optional default Project
- [x] The prompt appears after the app has been in front longer than the delay setting, when no Session runs or the matched Project differs from the running one
- [x] No prompt when already tracking the matched Project
- [x] "Not now" snoozes until the app leaves the front; "not today" until local midnight
- [x] Alt-tabbing doesn't repeat the prompt
- [x] Delay, snoozes and the no-prompt case are covered by core tests

## Notes

- Core: `Sources/HoursCore/WatchedApps.swift` (migration `v7-watched-apps`, table `watchedApp`, delay setting default 30 s, range 5-600 s). The prompt is computed from the clock (`pendingWatchedAppPrompt()`); the shell asks again via a one-shot timer, no polling.
- Defaults chosen: "longer than" = at least the delay; a quick alt-tab back (away for less than the delay) is the same stay (keeps dwell time and "not now"), so alt-tabbing doesn't repeat or reset the prompt; an app without a default Project (or with a Closed one) prompts only when nothing is running; Hours' own windows are ignored as front app.
- Needs a human click-through (not covered by tests): picking apps from the "Watched Apps…" window (installed-app scan of /Applications, /System/Applications, ~/Applications), real front-app notifications driving the tray prompt after the delay, and Start/Switch, "Not now", "Not today" buttons in the tray.
