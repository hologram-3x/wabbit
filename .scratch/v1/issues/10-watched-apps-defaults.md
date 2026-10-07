# 10: Watched Apps with default Projects

**What to build:** The freelancer marks apps as Watched Apps (e.g. VS Code, Photoshop), each with an optional default Project. Using one prompts them to start tracking.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** ready-for-agent

- [ ] Pick Watched Apps from installed apps, each with an optional default Project
- [ ] The prompt appears after the app has been in front longer than the delay setting, when no Session runs or the matched Project differs from the running one
- [ ] No prompt when already tracking the matched Project
- [ ] "Not now" snoozes until the app leaves the front; "not today" until local midnight
- [ ] Alt-tabbing doesn't repeat the prompt
- [ ] Delay, snoozes and the no-prompt case are covered by core tests
