# 02: Terminal working folder

**What to build:** when a terminal is in front, use the working folder of the shell in its front tab as the path for Project folders (so `claude` running in `~/DEV/wabbit` suggests Wabbit).

**Blocked by:** 01

**Status:** resolved (covered by 01 for Terminal; herdr moved to 04)

- [ ] Find the front tab's process: Terminal and iTerm via their scripting (tty of the selected tab), Ghostty via its window title or process tree; document what each supports
- [ ] Read the process's current folder with libproc (`proc_pidinfo` / `PROC_PIDVNODEPATHINFO`), no extra permission
- [ ] Re-check on tab switch where the app notifies it (AX title change), never by polling
- [ ] Unsupported terminal: fall back to window title rules
- [ ] Needs a human: several tabs and split panes in each terminal

## Answer

Probed on 2026-10-21 (only Terminal is installed here; iTerm and Ghostty untested).

- **Terminal needs no extra code.** Its focused window exposes the front tab's shell folder as `AXDocument` (`file:///Users/nic/`), because macOS's zsh setup (`/etc/zshrc_Apple_Terminal`) reports the folder to Terminal. Ticket 01 already reads `AXDocument` for Watched Apps, so a Watched Terminal in a Project folder suggests that Project.
- **A multiplexer hides the real folder.** With herdr running in the tab, the tab's process is `herdr`, started from `~`, so Terminal reports `/Users/nic` whatever pane is focused. herdr's own API knows the focused pane's folder (`herdr api snapshot`: `focused_pane_id`, and each pane's `cwd` / `foreground_cwd`). That integration is in ticket 04.
- Not done: libproc/tty lookups. Terminal doesn't need them, and they can't see inside a multiplexer either.
