# 11: Window-title rules via Accessibility

**What to build:** Watched App prompts pick the Project from the window title, e.g. VS Code on folder acme-site suggests ACME / Website.

**Blocked by:** 10 (Watched Apps with default Projects)

**Status:** ready-for-agent

- [ ] Ordered rules: "title contains" or "matches pattern" → Project
- [ ] Rules are evaluated in order, then the app's default Project
- [ ] Hours explains why the Accessibility permission is needed before asking
- [ ] Without the permission, prompts fall back to the app's default Project
- [ ] Rule order and fallback are covered by core tests
