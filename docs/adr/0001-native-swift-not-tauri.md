# Wabbit is native Swift, not Tauri

Unlike Chronicles, Octo, Zuzu and Vidego, which are opened, used and closed, Wabbit sits in the menu bar all day, so its resting footprint matters more than sharing the house stack. Wabbit is therefore written in Swift. The macOS app uses SwiftUI and AppKit, plus Apple's calendar, audio and idle-time APIs (EventKit, Core Audio, IOKit). All logic that doesn't depend on the OS lives in a separate Swift package: Clients, Projects, Sessions, rounding, Tax Rate, Effective Rate, SQLite storage and window-title rules.

## Considered Options

- **Tauri**: one codebase for every OS and the same stack as the other apps. Rejected because a system web view kept alive all day costs far more memory than a native menu-bar app, and every detection feature would need native code anyway.
- **Swift everywhere, SwiftUI everywhere**: not possible. Swift itself runs on Windows and Linux, but SwiftUI and AppKit are Apple-only.

## Consequences

- Windows and Linux are ports, not builds. Each reuses the shared Swift package and gets its own native UI and detection code (e.g. Swift on Windows with WinUI bindings, Swift on Linux with GTK/Adwaita bindings), or a different shell if those prove immature at the time.
- No code is shared with the Tauri apps. That's accepted, because they share no features with Wabbit.
