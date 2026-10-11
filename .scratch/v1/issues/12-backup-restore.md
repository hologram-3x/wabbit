# 12: Backup and restore

**What to build:** The freelancer backs up all their data to a single file and restores it on the same or another Mac.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] Back up to a single file (a consistent copy of the database)
- [x] Restore warns before replacing current data
- [x] A round-trip test restores a backup and gets identical Clients, Projects and Sessions

## Notes

- `Tracker.backup(to:)` / `restore(from:)` in `HoursCore/Backup.swift`, using GRDB online backup both ways (restore copies into the live database queue, so no file swapping and the app keeps running).
- Restore validates first (SQLite opens read-only, integrity_check, client/project/session tables, `hasBeenSuperseded` rejects newer schemas), keeps a temp safety copy and rolls back from it on failure, then runs pending migrations.
- UI: tray item "Backup & Restore…" opens a Backup window (NSSavePanel / NSOpenPanel + NSAlert confirmation) in `Sources/Hours/BackupView.swift`.
- Needs a human click-through: the save/open panels, the confirmation alert, and that the tray refreshes after a restore. A Session running at restore time is replaced by whatever the backup holds.
