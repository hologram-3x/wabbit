# Browser Profiles

A Browser Profile (e.g. Helium "OpenCom") can be assigned to a Client, so a browser used with several profiles suggests only that Client's work. See **Browser Profile** in `CONTEXT.md`.

## Behaviour

- Set in Watched Apps: a Watched browser lists its profiles, each with a Client picker (or none).
- While an assigned profile is in front, the Watched App prompt suggests only that Client's Open Projects: address rules, then document, then title rules, all restricted to that Client; else the Project last used for that Client. The profile wins over rules pointing to other Clients.
- Once a browser has at least one assigned profile: an unassigned profile, a Closed Client, or a Client with no Open Projects gives no prompt. A browser with no assigned profile behaves as today.
- Stored by profile folder (`Profile 1`), not name, so renaming in the browser keeps the assignment.
- v1: Chromium-based browsers only. Helium (`net.imput.helium`) is added to the supported Chromium list in `Sources/Wabbit/BrowserAddress.swift` (also enables its address reading).

## Detection (spike, 2026-11-19)

- Chromium: the focused window's AX title (`kAXTitleAttribute`, already read by `WindowTitleWatcher`) ends with ` - <Profile name>` when the browser has more than one profile: `Example Domain - Helium - Kipo`. AppleScript `name`/`title` does NOT include it. Match the title's end against `" - " + name` for each known profile name; don't split on " - " (page titles contain dashes). Verified switching Nic → Kipo → Nic windows. Cross-check signal: toolbar avatar `AXButton` whose title/description is the profile name (position varies; find by name).
- Profile names: `~/Library/Application Support/<vendor dir>/Local State` → `profile.info_cache` (`{"Default": {"name": "Nic"}, "Profile 1": {"name": "OpenCom"}, …}`). Helium dir: `net.imput.helium`; Chrome: `Google/Chrome`. Re-read when the browser comes to the front, when the profile list is shown, and when `Local State` changes (its folder is watched while the browser is a Watched App; bursts coalesce into one read 1 s after the last write).
- Single-profile browsers show no suffix; nothing to assign then.
- Spike scripts (temporary): `axdump.swift`, `profileprobe.swift` in the session scratchpad.

## Out of scope (separate issues)

- Firefox (issue 04), Safari (issue 05).
- Incognito / guest windows: untested; treat as unassigned.
