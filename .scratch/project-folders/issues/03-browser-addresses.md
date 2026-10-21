# 03: Browser addresses

**What to build:** match the front browser tab's address to Projects (e.g. a Figma file, a GitHub repo, a client's admin site).

**Blocked by:** 01

**Status:** needs-triage

- [ ] Core: Project addresses (prefix match on host + path), longest prefix wins; unit tests
- [ ] Shell: front tab URL via Apple Events for Safari, Chrome, Arc, Edge, Brave; ask for Automation permission with an explanation first, only when a Project has addresses
- [ ] Re-check on tab switch via AX title change, never by polling
- [ ] No permission or unsupported browser: fall back to title rules
- [ ] Privacy: the address is only compared locally, never stored or logged
