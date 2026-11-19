# 02: Browser Profiles for Firefox

Status: needs-triage

Blocked by: 01

Firefox runs each profile as its own process. The spike found the profile folder in the process's open files (`lsof -p <pid>` → `…/Firefox/Profiles/rnf820jv.dev-edition-default/places.sqlite`); in Swift via `proc_pidinfo` (`PROC_PIDLISTFDS` + `PROC_PIDFDVNODEPATHINFO`), no special permission. Map folder → name via `profiles.ini`. Untested with two profiles running at once; `profiles.ini` was not readable from the spike's session (TCC), check from Wabbit itself.
