# 01: Month / All toggle in the Overview

**What to build:** the Overview opens on the current calendar month and can switch to all time with a Month / All toggle, which replaces the free From/To range. The last choice is remembered. Sessions count in the month they start in; a running Session counts up to now. Fixed Projects keep Effective Rate, % of Estimate and warnings on all their time; only hours and prorated revenue follow the period. See `../spec.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Month / All toggle replaces the Date Range toggle and its From/To pickers; Export keeps its own range
- [x] Opens on Month; last choice remembered
- [x] Test: a Session started last month is excluded from Month, one started on the 1st is included; All includes both
- [x] Test: a Fixed Project's warnings are the same in Month and All
- [ ] Needs a human: switch Month / All and check the totals

## Notes

- `Tracker.currentMonthRange(calendar:)` (Money.swift) returns the 1st 00:00 to the next 1st, so a Session started just now still counts; the spec says "to now", equivalent since Sessions never start in the future.
- Choice stored under `@AppStorage("overviewMonthOnly")`; Export range untouched.
