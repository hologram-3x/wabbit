# 04: Claude Code and herdr (optional, developers)

**What to build:** precise "working in <folder>" signals from developer tools, fed into Project folders.

**Blocked by:** 01, 02

**Status:** needs-triage

- [ ] A tiny local entry point (URL scheme `wabbit://working?path=…` or a Unix socket in Application Support) that reports a folder as "in front now"
- [ ] Claude Code: document a `UserPromptSubmit` hook that calls it with the session's cwd; opt-in, off by default
- [ ] herdr: read open panes and their folders via its CLI when herdr is the front app
- [ ] Signals expire after a few minutes without new events, so a forgotten session doesn't keep suggesting a Project
- [ ] Docs page for setup
