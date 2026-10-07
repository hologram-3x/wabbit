# 04: Sessions window and Manual Sessions

**What to build:** The freelancer opens a window listing Sessions per Project or per day and can add a forgotten Session, or edit or delete an existing one. Hand-added Sessions are marked Manual.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** ready-for-agent

- [ ] Sessions are listed per Project and per day
- [ ] Add, edit and delete Sessions; added Sessions are marked Manual
- [ ] Adding or editing a Session that overlaps another is rejected, and the error names the conflicting Session
- [ ] A Session crossing midnight belongs to the day it started
- [ ] Adding a 2-hour Session for yesterday takes a few seconds
- [ ] Overlap and Manual rules are covered by core tests
