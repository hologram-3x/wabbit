# Wabbit

A native, always-on desktop menu-bar app with a small footprint (macOS first; Windows and Linux later as ports) for freelancers to track time worked per Project. Data stays on one machine, with a backup file. Its main purpose is to show whether a Client is underbilled or taking far more time than expected, not just to produce invoices. It can prompt you to start tracking when a meeting begins or a Watched App is in use.

## Language

**Client**:
Someone the freelancer works for. Has at least one Project.
_Avoid_: Customer, company, account

**Project**:
A body of work for one Client, with its own Rate. It is either Open (time can be added) or Closed (archived, read-only).
_Avoid_: Job, task, engagement

**Session**:
One continuous stretch of tracked time on one Project, with a start and an end. Only one Session runs at a time; a new prompt offers to switch. (Two at once, e.g. a meeting plus other work, may come later.) Sessions can be added, edited or deleted by hand, and hand-added ones are marked as Manual. A tracked Session that lasts under a minute is not kept.
_Avoid_: Entry, log, timer, timesheet row

**Rate**:
The hourly price agreed for a Project.
New Projects, and Projects without a Rate, get the Default Rate (the freelancer's own hourly price) from Config. A Project that already has a Rate is never changed.
_Avoid_: Price, fee, tariff

**Quick Start**:
A frequently used Project that can be started from the tray in one click. While a Session runs, the tray icon becomes Stop.
_Avoid_: Favorite, shortcut, pin

**Meeting Prompt**:
The popup offering to start a Session when a meeting is detected (microphone or camera in use). The Project is guessed from the matching calendar event.
_Avoid_: Notification, alert

**Watched App**:
An app the freelancer marks as work (e.g. Excel, VS Code, Photoshop). Using it triggers a prompt to start a Session. The Project is chosen by window-title rules, falling back to the app's default Project.
_Avoid_: Tracked app, monitored app

**Idle**:
A stretch with no input longer than the Idle Threshold (5 min to 1 h, set by the user). When the freelancer returns, they choose to keep, discard or split the idle time. Sessions are never stopped just because it's late.
_Avoid_: Away, inactive, pause

**Billing**:
An expectation for a Project: Hourly (just the Rate, the default for every new Project) or Fixed (an agreed price plus estimated hours). A Project can be set to no Billing; the app shows the tracked data with no warnings.
_Avoid_: Budget, contract, plan

**Effective Rate**:
The agreed price of a Fixed Project divided by the hours actually tracked. Compared against the freelancer's Rate to reveal underbilling.
_Avoid_: Real rate, actual rate

**Tax Rate**:
One global percentage of revenue that goes to tax (e.g. 22%).
_Avoid_: VAT, tax setting

**Net/Gross Switch**:
Changes how amounts are read. Gross: the revenue is what the Client pays, and the net is revenue × (1 − Tax Rate) (200 € → 156 €). Net: the revenue is what you keep, and the amount to ask is revenue ÷ (1 − Tax Rate) (200 € → 256.41 €).
_Avoid_: Tax Mode, add/consider

**Export**:
A CSV of Sessions, either Precise (actual durations) or Rounded: each Session is rounded to whole hours, down if it's at most 15 minutes past the hour and up otherwise (1h10 → 1h, 1h20 → 2h). The threshold and step are settings.
_Avoid_: Report, timesheet
