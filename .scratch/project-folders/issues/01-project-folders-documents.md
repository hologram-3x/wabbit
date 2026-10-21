# 01: Project folders and the front document

**What to build:** link folders to Projects, and suggest the Project when the front window's document (Accessibility `AXDocument`) is inside one of them.

**Status:** resolved

- [x] Core: Project folders (add, remove, list per Project), stored with the Project and included in backups
- [x] Core: path → Project lookup, deepest folder wins, Closed Projects skipped; unit tests for nesting, trailing slashes, `~`, symlinks resolved, case-insensitive volumes
- [x] Shell: read `AXDocument` of the focused window next to the window title (same AX observer, no polling); file URLs only
- [x] Priority: document match beats title rules, which beat the app's default Project
- [x] ~~Setting: "Suggest Projects from open documents in any app" (on by default)~~ Dropped (privacy): non-watched apps are never observed; documents only refine Watched Apps
- [x] UI: Project folders in Clients & Projects (folder picker via NSOpenPanel, list with remove)
- [ ] Needs a human: check real apps (Xcode, Pages, Preview, TextEdit, Word/Excel, VS Code) and note which report a document

## Notes

- Core: `Sources/WabbitCore/ProjectFolders.swift` (`ProjectFolder`, add/remove/list, `normalisedPath`, `projectForDocument`); migration `v12-project-folders` (table `projectFolder`, cascades with its Project, path unique `COLLATE NOCASE`, so one folder belongs to one Project: `ProjectFolderError.alreadyLinked`). Paths are normalised on add (expand `~`, standardise, resolve symlinks, no trailing slash) and the document path on each event; comparison is case-insensitive; deepest Open folder wins. Backups copy the whole DB, so folders are included (test: `foldersPersistAndAreInBackups`).
- `DetectionEvent.activeAppChanged` gained `documentPath: String? = nil`; the prompt picks document folder > title rules > default Project (`pendingWatchedAppPrompt`). Tests: `Tests/WabbitCoreTests/ProjectFoldersTests.swift`.
- Shell: `WindowTitles.swift` reads `kAXDocumentAttribute` (file URLs only) whenever it reads the title, same observer, no polling or timers. `ActiveAppObserver` now attaches the AX observer to Watched Apps only; other apps are reported by bundle ID with no title or document (before, titles were read for every front app and ignored by the core).
- UI: Clients & Projects shows each Project's folders (abbreviated with `~`, remove button) and "Add Folder…" (NSOpenPanel, directories only). Watched Apps' Accessibility copy mentions documents. No setting (dropped, see above).
- Not handled: a document change that doesn't change the window title isn't re-read until the next title/focus change (there's no AXDocument notification).
- Needs a human: with Accessibility on, check real apps and note which report a document. Expected: TextEdit, Preview, Pages/Numbers/Keynote, Xcode (the open file), most NSDocument apps; likely not VS Code/Electron apps; Word/Excel uncertain.
