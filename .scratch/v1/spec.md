# Hours v1

Status: ready-for-agent

## Problem Statement

As a freelancer, I don't really know how much time each Client takes. Calls start without me remembering to track them, I forget to stop timers, and I switch between Projects all day in Excel, VS Code or Photoshop. At the end of the month I invoice from memory or rough notes, so I can't tell whether a Fixed-price Project paid me a decent hourly amount or whether I'm quietly underbilling a Client. Existing time trackers are heavy, need accounts, want me to start every timer by hand, or treat time only as invoice lines rather than answering "is this Client worth it?".

## Solution

Hours is a native macOS menu-bar app that stays running all day with a very small footprint. It lets me track time per Project with one click (Quick Start), and it notices when I'm probably working: a call starts (microphone or camera in use, with the Project guessed from my calendar) or a Watched App is in front. Then it asks whether to start tracking. It handles forgotten timers through Idle detection, lets me fix Sessions by hand, and shows an Overview per Client and Project: hours, revenue net or gross, % of estimate used and the Effective Rate compared with my Rate. That makes underbilling visible. When it's time to invoice, I export a CSV of Sessions, Precise or Rounded. All data stays on my Mac, with a backup file.

## User Stories

### Clients and Projects
1. As a freelancer, I want to create a Client, so that I can group my work by who I work for.
2. As a freelancer, I want every Client to have at least one Project, so that time is always attached to concrete work.
3. As a freelancer, I want to create a Client and its first Project in a single step, so that setup takes seconds.
4. As a freelancer, I want to rename Clients and Projects, so that names stay accurate as work evolves.
5. As a freelancer, I want to set a Rate on each Project, so that different work for the same Client can be priced differently.
6. As a freelancer, I want to Close a Project, so that finished work is archived and no more time can be added to it.
7. As a freelancer, I want to Reopen a Closed Project, so that I can resume work I thought was finished.
8. As a freelancer, I want Closed Projects hidden from the tray and from prompts, so that my daily choices stay short.
9. As a freelancer, I want Closed Projects still visible in the Overview and Export, so that I can review past work.
10. As a freelancer, I want to be stopped from deleting a Client's last Project, so that a Client never ends up with no Projects.
11. As a freelancer, I want to attach email domains to a Client, so that meetings with that Client's people can be recognised.

### Tracking from the tray
12. As a freelancer, I want Hours to live in the menu bar with no Dock icon, so that it never gets in my way.
13. As a freelancer, I want Hours to start at login, so that I never forget to launch it.
14. As a freelancer, I want a Quick Start list of my most recently used Projects in the tray, so that I can start tracking in one click.
15. As a freelancer, I want an "Other…" choice in the tray, so that I can start any Open Project that isn't in Quick Start.
16. As a freelancer, I want the tray icon to change to Stop while a Session runs, so that I can see at a glance that I'm tracking.
17. As a freelancer, I want to see the running Session's Project and live duration in the tray, so that I know what I'm tracking right now.
18. As a freelancer, I want to stop the running Session with one click, so that ending work is as easy as starting it.
19. As a freelancer, I want starting a new Session to end the running one, so that only one Session ever runs at a time.
20. As a freelancer, I want the tray to show that a Session is running even after the Mac sleeps and wakes, so that tracking survives sleep.
21. As a freelancer, I want a running Session to survive the app restarting or the Mac rebooting, so that I don't lose tracked time.

### Sessions by hand
22. As a freelancer, I want a list of Sessions per Project or per day, so that I can review where my time went.
23. As a freelancer, I want to add a Session by hand with a Project, start and end, so that forgotten work still counts.
24. As a freelancer, I want hand-added Sessions marked Manual, so that I can tell tracked time from estimated time.
25. As a freelancer, I want to edit a Session's Project, start and end, so that I can fix mistakes.
26. As a freelancer, I want to delete a Session, so that wrong entries don't distort my numbers.
27. As a freelancer, I want overlapping Sessions rejected, with the conflicting Session shown, so that I never count the same time twice.
28. As a freelancer, I want very short Sessions always kept at their exact length, so that nothing is lost before export.
29. As a freelancer, I want Sessions crossing midnight to count towards the day they started, so that late-night work stays in one piece.
30. As a freelancer, I want to be unable to add Sessions to a Closed Project, so that archived work stays frozen.

### Idle
31. As a freelancer, I want to set an Idle Threshold between 5 minutes and 1 hour, so that idle detection fits how I work.
32. As a freelancer, I want to be asked what to do with idle time when I come back to a running Session, so that forgotten timers don't inflate my hours.
33. As a freelancer, I want to Keep the idle time, so that thinking or reading away from the keyboard still counts.
34. As a freelancer, I want to Discard the idle time, so that the Session ends where I actually stopped.
35. As a freelancer, I want to Split the idle time into its own Session that I can assign to another Project or drop, so that time spent on something else is recorded correctly.
36. As a freelancer who often works at night, I want Sessions never stopped just because it's late, so that night work is tracked normally.
37. As a freelancer, I want idle time below the threshold ignored, so that short breaks never trigger a prompt.

### Meeting Prompt
38. As a freelancer, I want a Meeting Prompt when my microphone or camera turns on, so that calls get tracked without me remembering.
39. As a freelancer, I want the Meeting Prompt to wait a few seconds before appearing, so that a quick mic test doesn't trigger it.
40. As a freelancer, I want the Meeting Prompt to suggest the Project of the Client whose email domain appears among the current calendar event's attendees, so that the right Project is already chosen.
41. As a freelancer, I want the Meeting Prompt to fall back to a Project whose keyword appears in the event title, so that meetings without Client emails are still guessed.
42. As a freelancer, I want the Meeting Prompt to fall back to my last-used Project when nothing matches, so that there is always a sensible default.
43. As a freelancer, I want to change the suggested Project in the prompt before accepting, so that a wrong guess costs one click.
44. As a freelancer, I want the Meeting Prompt to offer "Switch to …?" when another Session is running, so that I decide whether the call replaces my current work.
45. As a freelancer, I want ignoring a prompt to change nothing, so that useless meetings don't disrupt tracking.
46. As a freelancer, I want to be asked "Stop tracking?" when the microphone and camera turn off, so that call Sessions end on time without stopping automatically.
47. As a freelancer, I want Hours to work without calendar access, so that the Meeting Prompt still appears even if I deny the permission.

### Watched Apps
48. As a freelancer, I want to mark installed apps as Watched Apps, so that using them can prompt me to track work.
49. As a freelancer, I want to give each Watched App an optional default Project, so that the prompt has a sensible suggestion.
50. As a freelancer, I want ordered window-title rules ("contains" or "matches pattern" → Project), so that VS Code on one folder maps to one Project and on another folder to a different one.
51. As a freelancer, I want rules checked in order and then the app's default used, so that the outcome is predictable.
52. As a freelancer, I want a prompt only after a Watched App has stayed in front for a configurable number of seconds, so that alt-tabbing doesn't spam me.
53. As a freelancer, I want a prompt when a Watched App matches a different Project from the running Session, so that I can switch when I change work.
54. As a freelancer, I want no prompt when the running Session is already on the matched Project, so that I'm only asked when something changes.
55. As a freelancer, I want to snooze prompts for an app ("not now", "not today"), so that I can work without interruptions.
56. As a freelancer, I want Hours to explain why it needs the Accessibility permission, so that I can grant it with confidence for window-title rules.
57. As a freelancer, I want Watched Apps to still work by default Project when Accessibility is denied, so that the feature degrades gracefully.

### Money and underbilling
58. As a freelancer, I want to set one global Tax Rate, so that net and gross amounts are computed for me.
59. As a freelancer, I want a Net/Gross Switch, so that I can read amounts either as what the Client pays or as what I keep.
60. As a freelancer in Gross mode, I want to see net = revenue × (1 − Tax Rate), so that I know what stays in my pocket.
61. As a freelancer in Net mode, I want to see the amount to ask = revenue ÷ (1 − Tax Rate), so that I know what to invoice to keep my target.
62. As a freelancer, I want optional Billing on a Project, Hourly or Fixed, so that I can say what I expected from it.
63. As a freelancer, I want a Fixed Project to hold an agreed price and estimated hours, so that the app can compare expectations with reality.
64. As a freelancer, I want to see the Effective Rate of a Fixed Project, so that I know what I really earned per hour.
65. As a freelancer, I want the Effective Rate compared with the Project's Rate, so that underbilling is obvious.
66. As a freelancer, I want to see the % of estimated hours used, so that I notice overruns before the Project ends.
67. As a freelancer, I want red warnings only when Billing exists and the Project is over its estimate or below its Rate, so that warnings mean something.
68. As a freelancer, I want Projects without Billing shown with plain data and no warnings, so that Billing stays optional.
69. As a freelancer, I want an Overview per Client and per Project with hours, revenue (net and gross), Effective Rate and % of estimate, so that I can judge each Client at a glance.
70. As a freelancer, I want to filter the Overview by date range, so that I can look at a month or a quarter.
71. As a freelancer, I want money computed in whole cents, so that totals never drift from rounding errors.

### Export
72. As a freelancer, I want to export Sessions to CSV by Project, Client or date range, so that I can build invoices.
73. As a freelancer, I want a Precise Export with exact durations, so that I have the true record.
74. As a freelancer, I want a Rounded Export where each Session is rounded to whole hours (down if at most 15 minutes past the hour, up otherwise), so that I invoice in hours as I'm used to.
75. As a freelancer, I want the rounding threshold and step to be settings, so that I can match each Client's agreement.
76. As a freelancer, I want rounding applied only in the Export, never to stored Sessions, so that my data stays precise.
77. As a freelancer, I want the CSV columns to be date, client, project, start, end, duration, rate, amount and manual, so that it's ready for a spreadsheet.
78. As a freelancer, I want the CSV to open cleanly in Numbers and Excel, so that I don't fight encodings or separators.
79. As a freelancer, I want Precise Export totals to match the Overview, so that I can trust both.

### Backup and footprint
80. As a freelancer, I want to back up all my data to a single file, so that I can keep it safe.
81. As a freelancer, I want to restore from a backup file, so that I can recover on a new Mac or after a mistake.
82. As a freelancer, I want to be warned before a restore replaces my current data, so that I don't overwrite it by accident.
83. As a freelancer, I want Hours to use under 30 MB of memory and almost no CPU at rest, so that leaving it on all day costs nothing.
84. As a freelancer, I want Hours to update itself, so that I get fixes without reinstalling.
85. As a freelancer, I want all my data to stay on my Mac, so that my Client information is private.

## Implementation Decisions

- **Native Swift, per ADR 0001.** The macOS app uses SwiftUI (menu-bar extra) plus AppKit where needed. Minimum macOS 14.
- **Two modules:**
  - **Core package:** platform-independent. It holds Clients, Projects, Sessions, Billing, Idle resolution, prompt decisions, the Project guess for meetings, window-title rules, money (Rate, Tax Rate, Net/Gross, Effective Rate), Export (Precise and Rounded) and storage. No Apple-only imports, so the Windows and Linux ports can reuse it.
  - **macOS app shell:** UI and detection only. It turns OS signals into events for the core and turns the core's decisions into tray state and prompts.
- **Core public API (the test seam):**
  - **Commands:** create, rename, Close and Reopen Clients and Projects; set Rate and Billing; set Client email domains; start Session; stop Session; add, edit and delete a Session (Manual); resolve Idle (Keep, Discard, Split); configure Watched Apps and window-title rules; snooze; settings (Tax Rate, Net/Gross, Idle Threshold, rounding threshold and step, Watched App delay).
  - **Queries:** running Session, Quick Start list, Sessions by Project or day, Overview per Client and Project for a date range, Export (Precise or Rounded) for a Project, Client or date range.
  - **Detection input:** a single event feed into the core: microphone on/off, camera on/off, calendar event current, active app changed (with window title when available), user idle since time, user active again.
  - **Decisions out:** the core answers events with prompt decisions (show Meeting Prompt with suggested Project, offer switch, offer stop, show Watched App prompt, show Idle resolution). The shell only renders them.
- **Time comes from an injected clock** in the core. Nothing in the core reads the system time directly.
- **One Session at a time:** starting a Session stops the running one at the same instant. The schema doesn't prevent a future second concurrent Session, but the core enforces one.
- **Sessions store exact start and end instants.** A running Session has no end. Rounding exists only in Export.
- **Overlap rule:** adding or editing a Session that overlaps another is rejected, and the error names the conflicting Session.
- **Money:** Rates and prices are integer cents. Tax Rate is a percentage. Net/Gross conversions round to the cent once, at display or Export.
- **Effective Rate** = agreed price ÷ tracked hours, for Fixed Billing only. % of estimate = tracked hours ÷ estimated hours. A warning is raised only when Billing exists and (tracked > estimate, or Effective Rate < Rate).
- **Rounded Export:** applied per Session. Let the remainder be the duration beyond whole steps. If it's at most the threshold, round down; otherwise round up. Defaults: step 1 h, threshold 15 min.
- **Idle resolution:**
  - **Keep:** no change.
  - **Discard:** the Session ends at the idle start.
  - **Split:** the Session ends at the idle start, and a new Session covering the idle stretch is created, to be assigned to a Project or dropped.
- **No midnight cut-off.** A Session belongs to the day of its start.
- **Meeting Prompt:**
  - Shown when the microphone or camera has been on for about 10 s (debounced).
  - Project guess order: (1) a current calendar event attendee's email domain matches a Client's domains, giving that Client's most recently used Open Project; (2) a Project keyword appears in the event title; (3) the last-used Project.
  - Microphone and camera both off → offer "Stop tracking?".
- **Watched App prompt:**
  - Shown when the app has been in front longer than the delay setting, and either no Session is running or the matched Project differs from the running one.
  - Rules are evaluated in order, then the app's default Project.
  - Snoozes are kept per app until their expiry ("not now" = until the app leaves the front; "not today" = until local midnight).
- **Storage:** SQLite with versioned migrations. Backup = a consistent copy of the database file; restore replaces it after confirmation.
- **macOS detection in the shell:** event listeners for microphone and camera state and active-app changes; Accessibility API for window titles; idle time polled at most every 30 s; calendar via EventKit with full-access permission.
- **Footprint budget is an acceptance criterion:** under 30 MB of memory and about 0% CPU at rest; no windows created until opened.
- **Distribution:** notarized DMG with in-app updates (Sparkle).

## Testing Decisions

- **Good tests exercise external behaviour only**: commands in, queries and decisions out, through the core's public API. They never reach into tables or internal types, so storage and internals can change freely.
- **One seam: the core package's public API**, with:
  - a **fake clock** the test advances
  - a **fake detection feed** that emits microphone, camera, calendar, active-app and idle events
  - a **real in-memory SQLite** database (not a mocked store)
- **Covered through that seam:**
  - Client and Project lifecycle: last-Project rule, Closed Projects are read-only and hidden from Quick Start
  - one-Session rule and switching
  - Manual Sessions: add, edit, delete, overlap rejection with the conflicting Session named
  - Idle: below threshold ignored; Keep, Discard and Split produce the right Sessions; midnight crossing
  - money: Net and Gross both ways (200 € at 22% → 156 € and 256.41 €), Effective Rate (2,000 € fixed, 80 h → 25 €/h against 50 €/h), warning only when Billing exists
  - Rounded Export edges: exactly 15 min past the hour, 15 min 1 s, sub-hour Sessions, custom threshold and step; Precise totals match the Overview
  - Meeting Prompt: debounce, guess by email domain, then title keyword, then last-used; switch offer while running; ignore changes nothing; stop offer on mic and camera off
  - Watched App: delay, rule order, default fallback, no prompt when already on the matched Project, snoozes
  - backup and restore round-trip
- **Not tested automatically:** the macOS detection adapters and the UI. They're thin and checked by hand against real Zoom, Meet and Teams calls and real apps.
- **The footprint budget** is measured with Instruments over a full workday before release, not in unit tests.
- **Prior art:** none yet; this is the first code in the repo. The core's test suite sets the pattern for later ports.

## Out of Scope

- Two Sessions running at once (a meeting plus other work): possible later.
- Windows and Linux ports: later, reusing the core package (ADR 0001).
- Sync between machines, accounts or any server.
- Invoicing, payment tracking or sending documents to Clients.
- Silent background activity logging (tracking without a prompt and reviewing later).
- Per-Client Tax Rates. The Tax Rate is global in v1.
- Teams or multiple users.

## Further Notes

- "Hours" is a working name.
- Assumed: Client email domains for meeting matching are stored on the Client.
- Assumed: Quick Start shows the top N Open Projects by recent use, with N a small fixed number.
- The Accessibility permission is the only sensitive permission requested besides calendar access, and both are optional. Without them, prompts degrade to less specific suggestions.
