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
                    Label(c.rawValue.capitalized, systemImage: c == color ? "checkmark.circle.fill" : "circle.fill")
                }
                .tint(c.swiftUI)
            }
        } label: { ProjectDot(color: color) }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Project colour")
    }
}
