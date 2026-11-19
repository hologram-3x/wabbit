# 03: No prompt on unassigned profiles

**What to build:** once a browser has at least one profile assigned to a Client, a window of an unassigned profile, of a profile whose Client is Closed, or whose Client has no Open Projects, triggers no prompt. A browser with no assigned profile keeps today's behaviour.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] No prompt for unassigned profile / Closed Client / Client with no Open Projects, when the browser has ≥1 assignment
- [ ] Unchanged behaviour for a browser with no assignments (including single-profile browsers)
- [ ] Tests for each case
- [ ] Needs a human: Helium on the Nic profile gives no prompt; on OpenCom it does
