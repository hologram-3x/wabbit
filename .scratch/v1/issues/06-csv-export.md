# 06: CSV Export, Precise and Rounded

**What to build:** The freelancer exports Sessions for a Project, Client or date range as a CSV, either Precise or Rounded, ready for an invoice.

**Blocked by:** 05 (Money and Overview)

**Status:** resolved (needs a click-through and a check in Numbers/Excel)

- [x] Export by Project, Client or date range
- [x] Columns: date, client, project, start, end, duration, rate, amount, manual
- [x] Rounded is applied per Session: round down when the remainder is at most the threshold, otherwise up; threshold and step are settings (defaults 15 min and 1 h)
- [x] Every Session is stored precisely; rounding exists only in the Export
- [x] Precise totals match the Overview
- [ ] The CSV opens cleanly in Numbers and Excel
- [x] Tests cover exactly 15 min past the hour, 15 min 1 s, sub-hour Sessions, and a custom threshold and step

## Comments

- Core and tests done (Export.swift, ExportTests.swift); Export window opens from the tray ("Export…") and saves with NSSavePanel.
- CSV is UTF-8 with a BOM, comma-separated, amounts with a dot decimal; dates are UTC days and ISO 8601 instants.
- Needs a human: open an exported file in Numbers and Excel (unticked box), and click through the Export window.
