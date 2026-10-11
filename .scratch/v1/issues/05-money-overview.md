# 05: Money and Overview

**What to build:** Each Project gets a Rate and optional Billing (Hourly, or Fixed with agreed price and estimated hours). An Overview per Client and Project shows hours, revenue in Net or Gross, Effective Rate against the Rate, and % of estimate, so the freelancer can spot underbilling.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** resolved

- [x] A Rate per Project, plus a global Tax Rate and the Net/Gross Switch
- [x] Gross: net = revenue × (1 − Tax Rate). Net: amount to ask = revenue ÷ (1 − Tax Rate). Amounts are integer cents, rounded to the cent once
- [x] Billing is optional per Project: Hourly or Fixed (agreed price + estimated hours)
- [x] Effective Rate and % of estimate are shown for Fixed Billing
- [x] A warning shows only when Billing exists and the Project is over its estimate or under its Rate; without Billing, no warnings
- [x] The Overview can be filtered by date range
- [x] Tests: 200 € at 22% gives 156 € and 256.41 €; 2,000 € Fixed with 80 h gives 25 €/h against a 50 €/h Rate

## Notes (implementation)

- Core: `Sources/HoursCore/Money.swift` (migration `v3-money`; Tax Rate stored in basis points, 22% = 2200; settings in a `setting` table; defaults Tax 0, Gross). Tests: `Tests/HoursCoreTests/MoneyTests.swift` (19 tests total pass).
- Defaults chosen: sessions count in a date range when they start in it. A Fixed price is spread over the range pro rata to hours; Effective Rate and % of estimate use all tracked time. Warnings (over estimate / Fixed Effective Rate under Rate) only with Billing; Hourly cannot be under Rate. The Net/Gross Switch is applied to every amount shown (revenue, Effective Rate, Rate); warnings compare raw values.
- Needs a human click-through (UI not exercised by tests): tray "Overview…" window, Gross/Net picker, Tax Rate field (Return to save), date-range pickers, "Rate & Billing…" sheet (Hourly/Fixed), warning labels, Closed Projects listed greyed.
