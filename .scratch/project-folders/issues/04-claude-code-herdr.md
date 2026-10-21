# 04: Claude Code and herdr (optional, developers)

**What to build:** precise "working in <folder>" signals from developer tools, fed into Project folders.

**Blocked by:** 01, 02

**Status:** resolved (human checks below remain)

- [x] A tiny local entry point (~~URL scheme `wabbit://working?path=…`~~ dropped: any app or website could trigger it) a Unix socket in Application Support that reports a folder as "in front now"
- [x] Claude Code: document a `UserPromptSubmit` hook that calls it with the session's cwd; opt-in, off by default
- [x] herdr: when a Watched terminal is in front and its tab runs herdr, read the focused pane's folder from `herdr api snapshot` (`focused_pane_id`, then that pane's `foreground_cwd` or `cwd`) and use it as the document path; re-read when the terminal's window title changes (herdr retitles on pane focus), never by polling
- [x] Signals expire after a few minutes without new events, so a forgotten session doesn't keep suggesting a Project
- [x] Docs page for setup
- [ ] Needs a human: with the setting on and a Project folder for the focused pane, switch herdr panes in a Watched Terminal and check the prompt follows (relies on herdr retitling the Terminal window on pane focus)
- [ ] Needs a human: install the Claude Code hook from `docs/developer-tools.md`, send a prompt, check the Watched terminal suggests that folder's Project
- [ ] Needs a human: iTerm, Ghostty and the other listed terminals (only Terminal is installed here)

## Notes

- Setting: **Watched Apps → Developer tools → "Use folder signals from developer tools (herdr, Claude Code hook)"**, off by default (`setting` key `folderSignals`). It gates both herdr reads and the socket. Turning it off drops the current signal.
- Core: `Sources/WabbitCore/FolderSignals.swift`. New `DetectionEvent.folderSignal(path:)`; the core validates it (`validFolderSignal`: absolute, ≤ 1024 bytes, existing directory), keeps only the newest (any source) with its time, and `pendingWatchedAppPrompt` uses it only when the front Watched App is a terminal (`terminalBundleIDs`) and it's under 5 minutes old (`folderSignalLifetime`): signal > AXDocument > title rules > default. A signal outside every Project folder falls through to the next source. `HerdrSnapshot.focusedFolder` parses the snapshot JSON. Tests: `Tests/WabbitCoreTests/FolderSignalsTests.swift` (priority, newest wins, expiry, terminals only, off/on, validation, snapshot parsing). Parsing checked against the live `herdr api snapshot` (0.9.1; `foreground_cwd` is sometimes absent or null).
- herdr design: CLI, spawned on events only. `ActiveAppObserver` (WatchedAppsView.swift) runs `Herdr.focusedFolder` when a Watched terminal comes to the front or its window title changes (same AX observer as ticket 01; skipped if pid+title are unchanged), one read at a time, changes meanwhile coalesce into one more. Before spawning it checks, via libproc (`proc_listchildpids` + `proc_name`), that a `herdr` process runs under the terminal's pid (Terminal → login → zsh → herdr), so a terminal without herdr never spawns anything. The CLI is killed after 2 s; missing binary or any failure → nothing. Read-only (`herdr api snapshot` only). herdr's socket API has `events.subscribe` (`pane.focused`), which would avoid relying on window titles, but it means a long-lived connection to a versioned private protocol; the CLI is simpler and stable. Switch if pane focus doesn't retitle the terminal.
- Socket: `Sources/Wabbit/FolderSignals.swift` (`FolderSignalSocket`), `~/Library/Application Support/Wabbit/signal.sock`, 0600, DispatchSource accept, reads one line (1 s timeout, size capped), then closes. It exists only while the setting is on; removed on off, on quit, and at launch when off (a kill leaves the file). Checked by hand: with the setting on, `printf '/Volumes/SSD/DEV/Nicco/holo-3x/wabbit\n' | nc -U …/signal.sock` exits 0 at once; with it off the file is gone.
- Limits (ponytail): herdr is detected per terminal app, not per tab, so a plain tab next to a herdr tab gets herdr's folder; only the default herdr session is read. Non-terminal Watched Apps (VS Code, Cursor) ignore signals, per the privacy rule.
- Docs: `docs/developer-tools.md` (setting, priority, herdr, Claude Code hook with `nc -U`, `async: true`, `exit 0`).
