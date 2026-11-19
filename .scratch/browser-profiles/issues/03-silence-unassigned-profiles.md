# 03: No prompt on unassigned profiles

**What to build:** once a browser has at least one profile assigned to a Client, a window of an unassigned profile, of a profile whose Client is Closed, or whose Client has no Open Projects, triggers no prompt. A browser with no assigned profile keeps today's behaviour.

**Blocked by:** 02

**Status:** ready-for-agent

- [x] No prompt for unassigned profile / Closed Client / Client with no Open Projects, when the browser has ≥1 assignment
- [x] Unchanged behaviour for a browser with no assignments (including single-profile browsers)
- [x] Tests for each case
- [ ] Needs a human: Helium on the Nic profile gives no prompt; on OpenCom it does

## Notes

- Done together with 02 (commit "Browser Profiles for Chromium browsers"). "Client with no Open Projects" can only be a Closed Client (the last Project of a Client cannot be closed), so it is covered by the Closed Client case.
- Review fix: when a browser's profile names can't be read (`Local State` missing or unreadable) the core treats it as having no usable assignments, so normal rules and the app default apply instead of silence; names known but matching none of the title stay silent. The Browser profiles group shows "Can't read this browser's profiles: profiles are ignored until it can."
- Review fix: once a browser has ≥1 assigned profile (and its names are readable), its Default Project picker is disabled with the caption "Not used: the assigned profiles decide the Project."; it stays active with no assignments or unreadable names.
