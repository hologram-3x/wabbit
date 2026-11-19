# 02: Assign a Browser Profile to a Client

**What to build:** in Watched Apps, a Chromium browser with several profiles lists them by name (e.g. Helium: Nic, OpenCom, SmartMix, Kipo) with a Client picker each. While a window of an assigned profile is in front, the Watched App prompt suggests only that Client's Open Projects: the usual order (address, document, title rules) restricted to that Client, otherwise the Project last used for that Client. The profile wins over rules pointing to other Clients. The assignment survives renaming the profile in the browser. Detection notes are in `../spec.md`.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Profiles listed per Chromium Watched App, each assignable to a Client or none; saved and included in backups
- [ ] The front window's profile is recognised from its title, also when the page title contains dashes or one profile name ends another
- [ ] Prompt restricted to the assigned Client's Open Projects with the existing rule order; fallback to its last used Project
- [ ] A title rule for another Client's Project doesn't win over the profile
- [ ] Renaming a profile in the browser keeps its Client
- [ ] Tests for the above; browsers with no assignment behave as today
- [ ] Needs a human: Helium with Nic and OpenCom windows, assign OpenCom, check the prompt follows the window
