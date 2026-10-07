# 09: Calendar-based Project guess

**What to build:** The Meeting Prompt comes pre-filled with the right Project, guessed from the current calendar event.

**Blocked by:** 02 (Client and Project lifecycle), 08 (Meeting Prompt from microphone and camera)

**Status:** ready-for-agent

- [ ] Calendar access is requested; Hours works without it, falling back to the last-used Project
- [ ] Guess order: attendee email domain matches a Client's domains (that Client's most recently used Open Project), then a Project keyword in the event title, then the last-used Project
- [ ] Closed Projects are never suggested
- [ ] Each step of the guess order is covered by core tests with fake calendar events
