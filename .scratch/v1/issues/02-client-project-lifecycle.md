# 02: Client and Project lifecycle

**What to build:** The freelancer can rename Clients and Projects, Close a Project when the work ends and Reopen it later, and record each Client's email domains. Closed Projects stay in the archive but can't receive time.

**Blocked by:** 01 (Walking skeleton: track one Project from the menu bar)

**Status:** ready-for-agent

- [ ] Rename, Close and Reopen work for Clients and Projects
- [ ] A Client always has at least one Project (removing or closing the last one is handled as defined in the spec)
- [ ] Closed Projects reject new Sessions, both started and Manual
- [ ] Closed Projects are hidden from the tray and from prompts, but still appear in the Overview
- [ ] Email domains can be added to and removed from a Client
- [ ] Lifecycle rules are covered by tests at the core seam
