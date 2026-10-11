# 08: Meeting Prompt from microphone and camera

**What to build:** When a call starts (microphone or camera turns on), Hours shows a Meeting Prompt offering to start tracking the last-used Project, or to switch if another Session is running. When the call ends, it offers to stop.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] The prompt appears after the microphone or camera has been on for about 10 s (debounced)
- [x] Without other information, the suggested Project is the last-used one
- [x] While a Session runs, the prompt offers "Switch to …?"; ignoring it changes nothing
- [x] When the microphone and camera are both off, Hours offers "Stop tracking?" (never stops automatically)
- [x] Microphone and camera state come from OS event listeners, not polling
- [x] Prompt decisions are covered by core tests using the fake detection feed

## Comments

**Agent (implementation, branch `feat/08-meeting`):**

Defaults picked:
- Debounce **10 s** (`MeetingDebounce.seconds`). Microphone and camera count as one call: the clock starts when the first comes on and the call ends when both are off.
- Suggestion = last-used Open Project (Quick Start order). While a Session runs, the running Project is excluded, so "Switch to …?" offers the next last-used one; no prompt if there is no other Open Project. Ticket 09 plugs the calendar guess into `meetingSuggestion(excluding:)`.
- "Not now" (or answering) hides the prompt for the rest of the call; the next call prompts again. Ignoring leaves it up until the call ends; nothing changes.
- "Stop tracking?" is offered when both turn off after a call that lasted at least the debounce and a Session is running; it disappears if the Session is stopped some other way or a new call starts. Never automatic.
- Call state is in memory only, like Idle: no migration.
- The prompt shows in a small floating panel (top right, over full-screen apps, created only while a prompt is pending) and in the tray popover, with a Project picker to change the guess.
- Detection: Core Audio `kAudioDevicePropertyDeviceIsRunningSomewhere` on every input device and CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` on every camera, plus device-list listeners so newly plugged devices are watched. No polling; the only timer is a one-shot re-check when the debounce elapses.
- **No `NSMicrophoneUsageDescription` / `NSCameraUsageDescription`:** Hours only reads device state and never opens a device, so no TCC permission is involved. The built app launched without a permission prompt or crash.

Verified:
- `swift test`: 53 tests pass (10 new in `MeetingTests.swift`: debounce, short mic test, camera joining mid-call, last-used suggestion skipping Closed, accept with a changed Project, switch offer + ignore/dismiss, switch stops at the same instant, stop offer never automatic, no stop offer when nothing runs or stopped by hand, new call prompts again).
- `scripts/build-app.sh` builds; `build/Hours.app` launched and ran for a few seconds without crashing.

Needs a human (ready-for-human):
- Join a real Zoom / Meet / Teams call (mic only, then camera): the panel should appear about 10 s in; try Start, Switch, picking another Project, Not now; hang up and check "Stop tracking?".
- A quick mic test under 10 s (e.g. Voice Memos) must not prompt.
- Plug in a USB microphone or camera while Hours runs, then use it: it should prompt too.
- Known ceiling: a USB headset used only for playback can read as "microphone in use" (device-level property). If that causes false prompts, switch to per-process `kAudioProcessPropertyIsRunningInput`.
