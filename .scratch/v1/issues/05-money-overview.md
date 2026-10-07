# 05: Money and Overview

**What to build:** Each Project gets a Rate and optional Billing (Hourly, or Fixed with agreed price and estimated hours). An Overview per Client and Project shows hours, revenue in Net or Gross, Effective Rate against the Rate, and % of estimate, so the freelancer can spot underbilling.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** ready-for-agent

- [ ] A Rate per Project, plus a global Tax Rate and the Net/Gross Switch
- [ ] Gross: net = revenue × (1 − Tax Rate). Net: amount to ask = revenue ÷ (1 − Tax Rate). Amounts are integer cents, rounded to the cent once
- [ ] Billing is optional per Project: Hourly or Fixed (agreed price + estimated hours)
- [ ] Effective Rate and % of estimate are shown for Fixed Billing
- [ ] A warning shows only when Billing exists and the Project is over its estimate or under its Rate; without Billing, no warnings
- [ ] The Overview can be filtered by date range
- [ ] Tests: 200 € at 22% gives 156 € and 256.41 €; 2,000 € Fixed with 80 h gives 25 €/h against a 50 €/h Rate
