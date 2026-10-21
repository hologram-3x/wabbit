# 03: Browser addresses

**What to build:** match the front browser tab's address to Projects (e.g. a Figma file, a GitHub repo, a client's admin site).

**Blocked by:** 01

**Status:** resolved (human checks below remain)

- [x] Core: Project addresses (prefix match on host + path), longest prefix wins; unit tests
- [x] Shell: front tab URL via Apple Events for Safari, Chrome, Arc, Edge, Brave (and Vivaldi); ask for Automation permission with an explanation first, only when a Project has addresses
- [x] Re-check on tab switch via AX title change, never by polling
- [x] No permission or unsupported browser: fall back to title rules
- [x] Privacy: the address is only compared locally, never stored or logged
- [x] Firefox: probed, not readable (see Notes); falls back to title rules
- [ ] Needs a human: Watched Apps → Browser addresses → "Allow…" for Safari and Chrome (or Arc/Brave/Edge/Vivaldi), add an address to a Project, switch tabs, check the prompt follows the tab
- [ ] Needs a human: deny Automation for one browser and check prompts fall back to title rules with no error
- [ ] Needs a human: a signed release build (`SIGN_IDENTITY`, hardened runtime) still gets the Automation prompt (needs the new entitlement)

## Notes

- Core: `Sources/WabbitCore/ProjectAddresses.swift` (`ProjectAddress`, add/remove/list, `normalisedAddress`, `projectForAddress`); migration `v13-project-addresses` (registered last; table `projectAddress`: projectId cascade, `host`, `path`, unique (host, path), so one address belongs to one Project: `ProjectAddressError.alreadyLinked`; `.invalid` when there's no host). Normalising: trim, `https://` assumed when no scheme, host lowercased, `www.` dropped, port kept (`localhost:3000`), query, fragment and trailing slashes dropped; path case kept. Match: same host exactly (no subdomains), path equal or under the prefix by whole segments (`/acme` doesn't match `/acme-old`), longest prefix wins, Closed Projects/Clients skipped. Backups copy the whole DB, so addresses are included.
- New `DetectionEvent.browserAddress(bundleID:url:)`: accepted only for the app in front; kept in memory (`WatchedAppRuntime.address`, normalised) and cleared when the front app changes. Priority in `pendingWatchedAppPrompt`: folder signal (terminals only, unchanged) > address > AXDocument > title rules > default. Tests: `Tests/WabbitCoreTests/ProjectAddressesTests.swift` (normalising, host only, host+path, longest wins, `www.`, trailing slash, query/fragment ignored, Closed skipped, duplicate, priority, front app only, unwatched never prompts).
- Shell: `Sources/Wabbit/BrowserAddress.swift`. NSAppleScript (`with timeout of 2 seconds`, `tell application id …`): Safari `URL of current tab of front window`, Chrome/Brave/Edge/Arc/Vivaldi `URL of active tab of front window`. Run in `Task.detached`, one at a time, changes meanwhile coalesce (`ActiveAppObserver.readAddress`, same pattern as herdr); only Strings cross actors. Sent only when the front app is a Watched, supported browser and some Open Project has an address, from the existing AX title/focus callback (a tab switch retitles the window), never on a timer. The URL is emitted to the core and dropped; nothing logs it.
- Permission: event-driven reads never prompt: they first check `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` and read only when allowed. The macOS prompt appears only from Watched Apps → **Browser addresses** → "Allow…" (per Watched browser, after the explanation text); the row shows Allowed / Not allowed (System Settings path) / Open it to allow. Denied or not asked → nothing is sent, title rules apply. `NSAppleEventsUsageDescription` added to `App/Info.plist`; `App/Wabbit.entitlements` (`com.apple.security.automation.apple-events`) is passed only when signing with the hardened runtime (`scripts/build-app.sh`), which otherwise blocks Apple Events.
- Firefox (`org.mozilla.firefox`, the user's Developer Edition is `org.mozilla.firefoxdeveloperedition`): no AppleScript URL support. Read-only AX probe against the running Developer Edition: every window exposes only its frame (5 nodes: close/minimise/full-screen buttons and one empty group), `AXDocument` nil, no `AXURL`, no web area, no address field. Firefox builds its Accessibility tree only when an assistive technology turns it on (VoiceOver, or a client setting `AXEnhancedUserInterface` on the app). Setting that attribute was not tried (it changes Firefox's state and is known to slow window animations and confuse window managers), so Firefox is unsupported: Watched Apps says "Can't report its address: use title rules". Possible follow-up if wanted: set `AXEnhancedUserInterface` on a Watched Firefox and read the URL bar (`AXTextField` in the toolbar), after checking the side effects; note Firefox trims `https://` from the displayed address, which `normalisedAddress` handles.
- UI: Clients & Projects shows each Project's addresses under its folders (globe icon, remove button) and an "Add Address…" field (Return to save; pasted full URLs are normalised).
