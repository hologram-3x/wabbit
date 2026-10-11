# 13: In-app updates, footprint audit and v1.0

**What to build:** Hours updates itself and stays within its footprint budget over a real workday, and v1.0 ships.

**Blocked by:** 03 (Quick Start and tray state), 07 (Idle detection and resolution), 08 (Meeting Prompt from microphone and camera), 09 (Calendar-based Project guess), 10 (Watched Apps with default Projects), 11 (Window-title rules via Accessibility)

**Status:** ready-for-human

- [x] In-app updates via Sparkle
- [ ] An Instruments measurement over a full workday shows under 30 MB of memory and about 0% CPU at rest (human: steps in docs/release.md)
- [x] No windows are created until opened
- [x] Any overrun found is fixed (none found at rest, see notes)
- [ ] v1.0 is tagged and installs from GitHub Releases (human: steps in docs/release.md)

## Notes

### Footprint audit (agent, 2026-10-11, macOS 27 arm64, release build from `scripts/build-app.sh`, real database)

Launched with `open build/Hours.app`, idle for ~3 min, no Session running, popover never opened.

| | before Sparkle (main) | after (Sparkle embedded, not started) | after (Sparkle started, test key) |
| --- | --- | --- | --- |
| Physical footprint (`footprint`) | 18 MB | 18 MB | 19 MB |
| RSS (`ps`) | 80 MB | 70–80 MB | – |
| %CPU (`ps`, `top` 10×5 s) | 0.0 | 0.0 | – |
| CPU time after ~3 min | 0.16 s | 0.16 s | – |
| Windows owned (`CGWindowListCopyWindowInfo`) | 0 | 0 | 0 |

- The ~88 MB seen earlier is **RSS**, which counts clean shared pages of system frameworks (SwiftUI/AppKit `__TEXT` from the dyld shared cache) that every app maps. The budget's number is the physical footprint (what Activity Monitor's *Memory* column shows): 18 MB, of which ~10 MB is malloc and ~4 MB dirty framework data. Under budget, so no code change was needed.
- CPU: 0.0% throughout; CPU time grows ~0.01 s per few minutes (the 30 s idle poll). `top` idle-wakeups stayed flat. No timer fires while idle except the idle poll; the minute tick runs only while a Session runs and the Watched App check is one-shot.
- Windows: zero windows exist at rest. SwiftUI `Window` scenes and the `MenuBarExtra(.window)` popover are not instantiated until opened; the Meeting Prompt panel exists only while a prompt is pending.
- Not measured by the agent: memory after opening the popover and each window, and over a full day (the popover couldn't be driven from the command line). That is the human Instruments step.

### Sparkle

- Sparkle 2.10 via SwiftPM; "Check for Updates…" in the tray. `SUFeedURL` = GitHub Releases `latest/download/appcast.xml` of `hologram-3x/hours`; `SUEnableAutomaticChecks` on (daily, Sparkle's default interval).
- `SUPublicEDKey` comes from `SPARKLE_PUBLIC_ED_KEY` at build time (repo variable in CI). Without it the updater isn't started and the menu item is disabled, so dev builds never hit the feed.
- `scripts/build-app.sh` embeds `Sparkle.framework` in `Contents/Frameworks`, adds the `@executable_path/../Frameworks` rpath, drops the XPC services (Hours isn't sandboxed), and signs inside-out without `--deep`.
- The CI release job, on a tag, runs `generate_appcast` with the private key secret and creates the GitHub Release with the DMG and `appcast.xml`.
- **Private repo caveat:** Release assets of a private repo aren't publicly downloadable, so updates won't work until the appcast moves to a public releases repo or a hosted URL (or the repo goes public). Options in docs/release.md; decide before v1.0.
