import AppKit
import WabbitCore
import SwiftUI

extension ProjectColor {
    var swiftUI: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }

    /// A coloured, non-template dot: macOS menus draw SF Symbols monochrome and ignore `.tint`.
    @MainActor func dotImage(checked: Bool = false) -> NSImage {
        let color = NSColor(swiftUI)
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            if checked {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 4, dy: 4)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Finder-tag style dot before a Project name.
struct ProjectDot: View {
    let color: ProjectColor?
    var body: some View {
        Circle().fill((color ?? .gray).swiftUI).frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

/// The dot as a menu: pick one of the palette colours.
struct ProjectColorMenu: View {
    let color: ProjectColor?
    let pick: (ProjectColor) -> Void
    var body: some View {
        Menu {
            ForEach(ProjectColor.allCases, id: \.self) { c in
                Button { pick(c) } label: {
                    Label { Text(c.rawValue.capitalized) } icon: { Image(nsImage: c.dotImage(checked: c == color)) }
                }
            }
        } label: { Image(nsImage: (color ?? .gray).dotImage()) }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Project colour")
    }
}
