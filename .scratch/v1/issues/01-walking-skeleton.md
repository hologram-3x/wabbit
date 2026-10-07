# 01: Walking skeleton: track one Project from the menu bar

**What to build:** A freelancer installs a signed Hours app that lives only in the menu bar, creates a Client with its first Project, and starts and stops a Session from the tray. The Session is still there after quitting and relaunching. This also sets up the core package with its test seam (fake clock, fake detection feed, real in-memory SQLite) so every later ticket tests through it.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The app shows a tray icon and no Dock icon, and launches at login
- [ ] CI builds a signed, notarized DMG
- [ ] Creating a Client requires creating its first Project
- [ ] Start and Stop from the tray create one Session with exact start and end instants
- [ ] A running Session survives an app restart
- [ ] The core reads time only from an injected clock; a core test advances the fake clock and checks the Session's duration
- [ ] Storage uses SQLite with versioned migrations
