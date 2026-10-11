# 07: Idle detection and resolution

**What to build:** When the freelancer comes back after being Idle during a Session, Hours asks whether to keep, discard or split the idle time.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] Idle Threshold setting from 5 min to 1 h
- [x] Idle shorter than the threshold is ignored
- [x] Keep: no change. Discard: the Session ends at the idle start. Split: the Session ends at the idle start and a new Session covers the idle stretch, to be assigned or dropped
- [x] No midnight cut-off: a Session is never stopped because it's late
- [x] Idle time is polled at most every 30 s
- [x] Idle resolution is covered by core tests using the fake clock and fake idle events

## Comments

**Agent (implementation, branch `feat/07-idle`):**

Defaults picked:
- Idle Threshold default **15 min** (clamped 5 min–1 h); tray Picker offers 5/10/15/20/30/45/60.
- After **Split**, a new running Session resumes on the same Project from the return instant; the idle Session starts on that Project and the tray offers Assign / Drop.
- Pending Idle prompt is in-memory only (re-detected after relaunch via the 30 s poll).
- Migration `v2-idle` adds a `setting` table for the threshold.

Verified:
- `swift test`: 12 tests pass (6 existing + 6 Idle: threshold clamp, below-threshold ignored, Keep, Discard, Split+assign/drop, midnight crossing with Keep).
- `scripts/build-app.sh` builds ad-hoc signed `build/Hours.app`.

Needs a human (ready-for-human):
- **Idle click-through:** start a Session, leave the Mac idle past the threshold (or set threshold to 5 min), return, confirm the tray prompt; try Keep, Discard, and Split (then Assign / Drop).
- **Poll cadence:** confirm CPU stays near idle with the 30 s timer (Instruments optional; footprint is M8).
- **Existing DB:** first launch after this ticket applies `v2-idle` to `~/Library/Application Support/Hours/hours.sqlite`.
