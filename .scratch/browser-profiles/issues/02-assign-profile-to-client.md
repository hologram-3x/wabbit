# 02: Assign a Browser Profile to a Client

**What to build:** in Watched Apps, a Chromium browser with several profiles lists them by name (e.g. Helium: Nic, OpenCom, SmartMix, Kipo) with a Client picker each. While a window of an assigned profile is in front, the Watched App prompt suggests only that Client's Open Projects: the usual order (address, document, title rules) restricted to that Client, otherwise the Project last used for that Client. The profile wins over rules pointing to other Clients. The assignment survives renaming the profile in the browser. Detection notes are in `../spec.md`.

**Blocked by:** 01

**Status:** ready-for-agent

- [x] Profiles listed per Chromium Watched App, each assignable to a Client or none; saved and included in backups
- [x] The front window's profile is recognised from its title, also when the page title contains dashes or one profile name ends another
- [x] Prompt restricted to the assigned Client's Open Projects with the existing rule order; fallback to its last used Project
- [x] A title rule for another Client's Project doesn't win over the profile
- [x] Renaming a profile in the browser keeps its Client
- [x] Tests for the above; browsers with no assignment behave as today
- [ ] Needs a human: Helium with Nic and OpenCom windows, assign OpenCom, check the prompt follows the window

## Notes

- Core: `Sources/WabbitCore/BrowserProfiles.swift`; migration `v15-browser-profiles` (registered last; table `browserProfile`: `bundleID` → `watchedApp` cascade, `folder`, `clientId` → `client` cascade, primary key (bundleID, folder)). API: `browserProfiles(bundleID:)` (folder → Client id), `setBrowserProfileClient(bundleID:folder:clientId:)` (nil unassigns), `setBrowserProfileNames(bundleID:_:)` (folder → name, in memory only, supplied by the shell), `Tracker.profileFolder(title:names:)`. Removing the browser from Watched Apps or deleting the Client drops its assignments (like title rules). Backups copy the whole DB, so assignments are included (tested).
- Matching: the title must end with `" - " + name`; never split; longest matching name wins (`Kipo` vs `Acme - Kipo`). Renaming keeps the assignment because it is stored by folder and names are re-read.
- Prompt (`pendingWatchedAppPrompt`): when the browser has ≥1 assignment, the front window's profile must be assigned to a Client with an Open Project, else no prompt (unassigned profile, no suffix, title unknown/no Accessibility, Closed Client). Then folder signal, address, AXDocument and title rules are all restricted to that Client (`clientId` filter added to `projectForNormalised`, `projectForNormalisedAddress`, `resolveProject`; a shorter address of the Client beats a longer one of another Client), and the browser's default Project is replaced by the Client's last used Open Project (latest Session), else its first Open Project by name. Browsers with no assignments are unchanged.
- "Client with no Open Projects" can only be a Closed Client: a Client can't close its last Project (`WabbitError.lastProject`).
- Shell: Helium (`net.imput.helium`, scriptable with Chrome's sdef) added to `BrowserAddress` (enables address reading). `Sources/Wabbit/BrowserProfiles.swift` (`ChromiumProfiles`) reads `~/Library/Application Support/<dir>/Local State` → `profile.info_cache` for Chrome, Brave, Edge, Vivaldi, Helium. Arc skipped: no `Local State` on this Mac (profiles belong to Spaces), titles carry no profile. Names are re-read each time a Watched Chromium browser comes to the front (`ActiveAppObserver`) and when Watched Apps shows the list, instead of "when matching misses" (the core can't call the shell). Titles and names are never logged.
- UI: Watched Apps → each Watched Chromium browser → "Browser profiles" (disclosure group): one Client picker per profile (None + Open Clients; an assigned Closed Client is shown as "(Closed)" so it can be cleared). With a single profile: "Only one profile: nothing to assign."
- Tests: `Tests/WabbitCoreTests/BrowserProfilesTests.swift` (title parsing with dashes and nested names, storage, no-assignment browser unchanged, restriction of address and title rules, fallback to last used / first Open Project, no-prompt cases, rename, backup).
