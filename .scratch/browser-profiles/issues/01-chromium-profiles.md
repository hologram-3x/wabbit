# 01: Browser Profiles for Chromium browsers

Status: ready-for-agent

**What to build:** see `../spec.md`.

- [ ] Add Helium (`net.imput.helium`) to the Chromium bundle-id list
- [ ] Core: profile assignment table (Watched App bundle id + profile folder → Client), migration, backup included
- [ ] Core: profile resolved from the window title's end against known names; prompt restricted to the Client's Open Projects with the existing rule order, fallback to the Client's last used Project; no prompt for unassigned / Closed / no-Open-Project when the browser has ≥1 assignment
- [ ] Unit tests: title parsing (dashes in page titles, name that is a suffix of another name), restriction, fallback, no-prompt cases, browser with no assignments unchanged, rename keeps assignment
- [ ] Shell: read `Local State` profile names per Chromium browser; Watched Apps UI lists profiles with a Client picker
- [ ] Needs a human: Helium with OpenCom and Nic windows, check prompts follow the window
