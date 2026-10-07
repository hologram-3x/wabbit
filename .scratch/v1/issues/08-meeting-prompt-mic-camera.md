# 08: Meeting Prompt from microphone and camera

**What to build:** When a call starts (microphone or camera turns on), Hours shows a Meeting Prompt offering to start tracking the last-used Project, or to switch if another Session is running. When the call ends, it offers to stop.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** ready-for-agent

- [ ] The prompt appears after the microphone or camera has been on for about 10 s (debounced)
- [ ] Without other information, the suggested Project is the last-used one
- [ ] While a Session runs, the prompt offers "Switch to …?"; ignoring it changes nothing
- [ ] When the microphone and camera are both off, Hours offers "Stop tracking?" (never stops automatically)
- [ ] Microphone and camera state come from OS event listeners, not polling
- [ ] Prompt decisions are covered by core tests using the fake detection feed
