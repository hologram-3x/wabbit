# 01: Month / All toggle in the Overview

Status: ready-for-agent

**What to build:** see `../spec.md`.

- [ ] Replace the Date Range toggle and From/To pickers with a Month / All toggle, opening on Month
- [ ] Month range = start of current calendar month to now, passed to `Tracker.overview(range:)`
- [ ] Remember the last choice (`@AppStorage`)
- [ ] Unit test for the current-month range (FakeClock): a Session started last month is excluded, one started on the 1st is included
- [ ] Needs a human: switch Month / All and check totals; Fixed Project warnings unchanged between the two
