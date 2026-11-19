# Overview: Month / All

The Overview shows the current month by default, with a toggle to see all time.

## Behaviour

- A **Month / All** segmented toggle replaces the current "Date Range" toggle and its From/To pickers (`Sources/Wabbit/OverviewView.swift`). The Export keeps its own date range.
- **Month** = the current calendar month (1st 00:00 to now, local calendar). No arrows to earlier months.
- Opens on Month; the last choice is remembered.
- Sessions count in the month they start in (unchanged: `Tracker.overview(range:)` filters on `session.start`); a running Session counts up to now.
- Fixed Projects: unchanged. Revenue in the period is prorated by hours (`Money.swift` ~206); Effective Rate, % of Estimate and warnings use all-time totals.

## Out of scope

- Browsing earlier months, custom ranges in the Overview.
