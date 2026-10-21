# Project folders

Wabbit suggests the Project you're working on from what is in front of you, not only from which app is in front. The general mechanism is **Project folders**: a folder linked to a Project. Any front window showing a file (or a shell) inside that folder points to that Project. It works for anyone with files on disk; developer tools are optional extra sources.

## Behaviour

- A Project has zero or more Project folders. A path matches a folder when it is that folder or inside it; the deepest matching folder wins (`~/DEV/acme/site` beats `~/DEV/acme`).
- Sources of "what is in front", in order of specificity. The most specific match wins:
  1. the front window's document path (Accessibility `AXDocument`)
  2. the working folder of the shell in the front terminal window
  3. the front browser tab's address, matched against Project addresses (ticket 03); for a Watched browser it comes before the document path
  4. existing window-title rules
  5. the Watched App's default Project
- A match never starts tracking by itself. It feeds the existing Watched App prompt ("Track time for <App>?", Start <Project> / Not now / Not today, notification included), with the same delay and snooze rules. Only Watched Apps are read: an app not in Watched Apps is never observed (no title, document, shell or tab), so a match only refines which Project a Watched App suggests.
- Closed Projects never match.
- Everything stays on the Mac; no paths or addresses leave it.

## Out of scope

- Tracking which file was edited, or file-level time reports.
- Automatic tracking without a prompt.

## Open questions

- ~~Should a match on a non-watched app prompt at all, or only refine watched ones?~~ Resolved: only refine. Non-watched apps are never observed (privacy).
- Terminals with several tabs: is the front tab reliably detectable in Terminal, iTerm and Ghostty?
