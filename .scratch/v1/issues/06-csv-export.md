# 06: CSV Export, Precise and Rounded

**What to build:** The freelancer exports Sessions for a Project, Client or date range as a CSV, either Precise or Rounded, ready for an invoice.

**Blocked by:** 05 (Money and Overview)

**Status:** ready-for-agent

- [ ] Export by Project, Client or date range
- [ ] Columns: date, client, project, start, end, duration, rate, amount, manual
- [ ] Rounded is applied per Session: round down when the remainder is at most the threshold, otherwise up; threshold and step are settings (defaults 15 min and 1 h)
- [ ] Every Session is stored precisely; rounding exists only in the Export
- [ ] Precise totals match the Overview
- [ ] The CSV opens cleanly in Numbers and Excel
- [ ] Tests cover exactly 15 min past the hour, 15 min 1 s, sub-hour Sessions, and a custom threshold and step
