# 01: Project folders and the front document

**What to build:** link folders to Projects, and suggest the Project when the front window's document (Accessibility `AXDocument`) is inside one of them.

**Status:** needs-triage

- [ ] Core: Project folders (add, remove, list per Project), stored with the Project and included in backups
- [ ] Core: path → Project lookup, deepest folder wins, Closed Projects skipped; unit tests for nesting, trailing slashes, `~`, symlinks resolved, case-insensitive volumes
- [ ] Shell: read `AXDocument` of the focused window next to the window title (same AX observer, no polling); file URLs only
- [ ] Priority: document match beats title rules, which beat the app's default Project
- [ ] Setting: "Suggest Projects from open documents in any app" (on by default)
- [ ] UI: Project folders in Clients & Projects (folder picker via NSOpenPanel, list with remove)
- [ ] Needs a human: check real apps (Xcode, Pages, Preview, TextEdit, Word/Excel, VS Code) and note which report a document
