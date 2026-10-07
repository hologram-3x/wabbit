# 07: Idle detection and resolution

**What to build:** When the freelancer comes back after being Idle during a Session, Hours asks whether to keep, discard or split the idle time.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** ready-for-agent

- [ ] Idle Threshold setting from 5 min to 1 h
- [ ] Idle shorter than the threshold is ignored
- [ ] Keep: no change. Discard: the Session ends at the idle start. Split: the Session ends at the idle start and a new Session covers the idle stretch, to be assigned or dropped
- [ ] No midnight cut-off: a Session is never stopped because it's late
- [ ] Idle time is polled at most every 30 s
- [ ] Idle resolution is covered by core tests using the fake clock and fake idle events
