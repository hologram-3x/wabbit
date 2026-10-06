# Hours v1 plan

Vocabulary follows [CONTEXT.md](./CONTEXT.md). Architecture decisions live in [docs/adr](./docs/adr/).

## Goal

A freelancer leaves Hours in the menu bar all week. Calls and work in Watched Apps prompt them to track time, they barely touch it otherwise, and at the end of the month they can see per Client whether they're underbilling. Then they export a CSV for the invoice.

## Scope

**In v1 (macOS only)**
- Clients and Projects (Open/Closed), each Project with its own Rate
- Tray: Quick Start for frequent Projects; the icon becomes Stop while a Session runs
- One Session at a time. Prompts offer to switch.
- Manual Sessions (add, edit, delete), marked as Manual
- Optional Billing (Hourly or Fixed + estimated hours) → Effective Rate and % of estimate
- Tax Rate and the Net/Gross Switch
- Export to CSV, Precise or Rounded
- Idle detection with a threshold you set (5 min–1 h)
- Meeting Prompt (microphone or camera in use, Project guessed from the calendar)
- Watched Apps with window-title rules
- Backup and restore to a file

**Later**
- Two Sessions at once (e.g. a meeting plus other work)
- Windows and Linux ports ([ADR 0001](./docs/adr/0001-native-swift-not-tauri.md))
- Sync between machines

## Footprint budget

Hours is always running, so these are acceptance criteria, measured in M8:
- **< 30 MB RAM** at rest, **~0% CPU** at rest
- Use OS event listeners instead of polling wherever they exist (microphone and camera state, active app changes)
- Only idle detection polls, at most once every 30 s
- No windows are created until they're opened

## Stack

- **Swift and SwiftUI**, minimum macOS 14:
  - `MenuBarExtra` for the tray
  - AppKit where SwiftUI falls short
- **`HoursCore`**: a Swift package with no Apple-only imports, so the Windows and Linux ports can reuse it. It holds:
  - the domain: Clients, Projects, Sessions, Billing
  - rounding, Tax Rate and Effective Rate
  - window-title rules
  - storage
- **Storage:** SQLite through GRDB.swift
- **macOS APIs (detection, only in the app target):**
  - **Microphone in use:** Core Audio `kAudioDevicePropertyDeviceIsRunningSomewhere` listener
  - **Camera in use:** CoreMediaIO, the equivalent property
  - **Calendar:** EventKit (`requestFullAccessToEvents`)
  - **Active app:** `NSWorkspace` notifications, no permission needed
  - **Window titles:** Accessibility API (`AXUIElement`), which needs the Accessibility permission (avoids Screen Recording)
  - **Idle:** `CGEventSource.secondsSinceLastEventType`, no permission needed
  - **Launch at login:** `SMAppService`
- **Updates:** Sparkle. Releases are a notarized DMG.

## Milestones

Each milestone ends with something you can demo.

### M0 · Skeleton
- An Xcode project with a menu-bar-only app (no Dock icon) and the `HoursCore` package
- GRDB schema with migrations
- Launch at login
- CI builds and notarizes a DMG
- **Done when:** a signed app shows a tray icon and survives a reboot.

### M1 · Track by hand
- Create, rename, Close and Reopen Clients and Projects. A Client must have at least one Project. Closed Projects are read-only and hidden from the tray.
- From the tray:
  - Quick Start lists the top N Projects by recent use, plus "Other…"
  - Stop
  - the running Session shows its live duration
- Only one Session at a time. Starting another stops the current one.
- **Done when:** a day of real work is tracked from the tray only.

### M2 · Sessions window
- A list of Sessions per Project or day
- Add, edit and delete Sessions. Hand-added Sessions are marked Manual.
- Overlapping Sessions are rejected, with the conflicting Session shown
- **Done when:** a forgotten 2-hour job from yesterday can be added in a few seconds.

### M3 · Money and underbilling
- A Rate per Project, plus a global Tax Rate and the Net/Gross Switch:
  - **Gross:** net = revenue × (1 − Tax Rate)
  - **Net:** amount to ask = revenue ÷ (1 − Tax Rate)
- Optional Billing per Project:
  - **Hourly:** Rate only
  - **Fixed:** agreed price + estimated hours → Effective Rate and % of estimate used
- **Overview per Client and Project:** hours, revenue (net and gross), Effective Rate compared with the Rate, and % of estimate. Shown in red only when Billing exists and the Project is over its estimate or under its Rate. Without Billing, the data is shown with no warnings.
- Core logic gets unit tests (`HoursCore` tests): money in integer cents, tax in both directions, Effective Rate.
- **Done when:** a Fixed Project at €2,000 with 80 h tracked shows €25/h against a €50/h Rate.

### M4 · Export
- CSV per Project, Client or date range, either Precise or Rounded.
- Every Session is always tracked and stored precisely, whatever its length. Rounding happens only in the Export.
- Rounded works per Session: round down to the whole hour when at most the threshold (15 min) past it, otherwise round up. The threshold and step are settings.
- Columns: date, client, project, start, end, duration, rate, amount, manual.
- Unit tests for the rounding edges: exactly 15 min, 15:01, sub-hour Sessions.
- **Done when:** the CSV opens cleanly in Numbers and Excel, and the numbers match the Overview.

### M5 · Idle
- **Idle Threshold** setting (5 min–1 h).
- When you come back after going idle during a Session: **Keep**, **Discard idle time**, or **Split** (the idle time becomes a separate Session you can assign or drop).
- No cut-off at midnight. Sessions crossing midnight count towards the day they started.
- **Done when:** leaving the Mac for 40 minutes mid-Session produces the prompt, and each choice gives the right Sessions.

### M6 · Meeting Prompt
- The microphone or camera turning on (debounced ~10 s) shows the Meeting Prompt.
- **Project guessed** from the current calendar event:
  - an attendee's email domain matches a Client's domain list
  - otherwise, a title keyword matches a Project
  - otherwise, the last-used Project
- While a Session is running, the prompt offers "Switch to …?". Ignoring it changes nothing.
- The microphone or camera turning off offers "Stop tracking?" (not automatic).
- **Done when:** a Zoom, Meet or Teams call with a Client's address in the invite prompts with that Client's Project already chosen.

### M7 · Watched Apps
- Pick apps from the installed apps list. Each has an optional default Project.
- Window-title rules: "title contains / matches regex → Project". Rules are checked in order, then the app's default is used.
- The prompt appears when a Watched App stays in front for more than N seconds (setting) and no Session is running, or a different Project is matched.
- Snooze per app: "not now", "not today".
- **Done when:** opening VS Code on `acme-site` prompts for ACME / Website, and the prompt doesn't repeat every alt-tab.

### M8 · Backup and release
- Back up and restore to a single file (a copy of the SQLite database).
- Measure the footprint budget with Instruments over a full workday, and fix whatever exceeds it.
- Sparkle updates, notarized DMG, v1.0 tag.
- **Done when:** v1.0 installs from GitHub Releases and stays within the footprint budget.

## Open questions

- **Do Client email domains** for the meeting match live on the Client? Assumed yes.
- **Name.** "Hours" is still a working name.
