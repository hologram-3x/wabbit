# 04: Claude Code and herdr (optional, developers)

**What to build:** precise "working in <folder>" signals from developer tools, fed into Project folders.

**Blocked by:** 01, 02

**Status:** needs-triage

- [ ] A tiny local entry point (URL scheme `wabbit://working?path=…` or a Unix socket in Application Support) that reports a folder as "in front now"
- [ ] Claude Code: document a `UserPromptSubmit` hook that calls it with the session's cwd; opt-in, off by default
- [ ] herdr: when a Watched terminal is in front and its tab runs herdr, read the focused pane's folder from `herdr api snapshot` (`focused_pane_id`, then that pane's `foreground_cwd` or `cwd`) and use it as the document path; re-read when the terminal's window title changes (herdr retitles on pane focus), never by polling
- [ ] Signals expire after a few minutes without new events, so a forgotten session doesn't keep suggesting a Project
- [ ] Docs page for setup
