# 11: Window-title rules via Accessibility

**What to build:** Watched App prompts pick the Project from the window title, e.g. VS Code on folder acme-site suggests ACME / Website.

**Blocked by:** 10 (Watched Apps with default Projects)

**Status:** resolved

- [x] Ordered rules: "title contains" or "matches pattern" → Project
- [x] Rules are evaluated in order, then the app's default Project
- [x] Hours explains why the Accessibility permission is needed before asking
- [x] Without the permission, prompts fall back to the app's default Project
- [x] Rule order and fallback are covered by core tests

## Notes

- Core: `Sources/HoursCore/TitleRules.swift` (table `titleRule`, migration `v8-title-rules`). "contains" is case/diacritic-insensitive; "pattern" is a case-insensitive regex searched anywhere in the title; invalid regex is rejected on add. First matching rule whose Project is Open wins, else the app's default Project (Closed Projects skipped). A title change within the same stay re-picks the Project without resetting the prompt delay.
- Shell: `Sources/Hours/WindowTitles.swift` (`AXObserver`, no polling) feeds `activeAppChanged(windowTitle:)`; rules editor sits under each app in Watched Apps. The Accessibility prompt only appears when the user clicks "Grant Accessibility…" under an explanation. Without it the title is nil and rules are skipped.
- Needs a human: grant Accessibility to Hours.app (ad-hoc rebuilds may need re-granting) and check real windows (e.g. VS Code folder title, title change on tab switch). Permission granted mid-stay applies from the next app activation. AX adapter and UI are untested by automation.
