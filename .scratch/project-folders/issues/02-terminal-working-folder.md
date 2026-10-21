# 02: Terminal working folder

**What to build:** when a terminal is in front, use the working folder of the shell in its front tab as the path for Project folders (so `claude` running in `~/DEV/wabbit` suggests Wabbit).

**Blocked by:** 01

**Status:** needs-triage

- [ ] Find the front tab's process: Terminal and iTerm via their scripting (tty of the selected tab), Ghostty via its window title or process tree; document what each supports
- [ ] Read the process's current folder with libproc (`proc_pidinfo` / `PROC_PIDVNODEPATHINFO`), no extra permission
- [ ] Re-check on tab switch where the app notifies it (AX title change), never by polling
- [ ] Unsupported terminal: fall back to window title rules
- [ ] Needs a human: several tabs and split panes in each terminal
