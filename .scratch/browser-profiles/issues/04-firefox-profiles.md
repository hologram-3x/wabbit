# 04: Browser Profiles for Firefox

**What to build:** the same profile → Client assignment for Firefox. Each Firefox profile runs as its own process; the spike found the profile folder among the process's open files, mapped to a name via Firefox's profiles list. See `../spec.md`.

**Blocked by:** 02

**Status:** needs-triage

- [ ] Verify with two Firefox profiles running at once, and that Wabbit can read the profiles list
- [ ] Firefox profiles listed and assignable like Chromium ones
