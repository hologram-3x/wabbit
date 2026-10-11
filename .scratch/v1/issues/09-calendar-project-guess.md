# 09: Calendar-based Project guess

**What to build:** The Meeting Prompt comes pre-filled with the right Project, guessed from the current calendar event.

**Blocked by:** 02 (Client and Project lifecycle), 08 (Meeting Prompt from microphone and camera)

**Status:** resolved

- [x] Calendar access is requested; Hours works without it, falling back to the last-used Project
- [x] Guess order: attendee email domain matches a Client's domains (that Client's most recently used Open Project), then a Project keyword in the event title, then the last-used Project
- [x] Closed Projects are never suggested
- [x] Each step of the guess order is covered by core tests with fake calendar events

## Notes

- Core: `Sources/HoursCore/CalendarGuess.swift` (plugs into `meetingSuggestion`); EventKit adapter: `Sources/Hours/CalendarAccess.swift`, queried on mic/camera on; access requested lazily, denial = no event = last-used fallback. No migration.
- Defaults chosen: a Project's "keyword" is its name (case-insensitive substring of the title, longest name wins, ties by recency); subdomains of a Client domain match; all-day events ignored; a guess equal to the running Project is skipped (fallback applies).
- Needs a human: grant Calendar access on first call, and try a real event with attendees (Client domain set) while the mic is on.
