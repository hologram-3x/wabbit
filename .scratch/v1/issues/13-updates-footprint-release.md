# 13: In-app updates, footprint audit and v1.0

**What to build:** Hours updates itself and stays within its footprint budget over a real workday, and v1.0 ships.

**Blocked by:** 03 (Quick Start and tray state), 07 (Idle detection and resolution), 08 (Meeting Prompt from microphone and camera), 09 (Calendar-based Project guess), 10 (Watched Apps with default Projects), 11 (Window-title rules via Accessibility)

**Status:** ready-for-agent

- [ ] In-app updates via Sparkle
- [ ] An Instruments measurement over a full workday shows under 30 MB of memory and about 0% CPU at rest
- [ ] No windows are created until opened
- [ ] Any overrun found is fixed
- [ ] v1.0 is tagged and installs from GitHub Releases
