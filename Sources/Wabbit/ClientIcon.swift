import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WabbitCore

/// A Client's icon tile: its custom SVG, or its initials in white on `color` (the Project shown next to it;
/// Clients have no colour of their own). Rounded square, corner 25%.
struct ClientIcon: View {
    let client: Client?
    let color: ProjectColor?
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 4, style: .continuous)
        Group {
            if let image = client?.icon.flatMap(Self.image) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                shape.fill((color ?? .gray).swiftUI)
                    .overlay {
                        Text(Self.initials(client?.name ?? "?"))
                            .font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                            .minimumScaleFactor(0.5).lineLimit(1)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    /// First letter of up to two words.
    static func initials(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    // ponytail: unbounded cache keyed by SVG text; a handful of Clients, so it never grows much.
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor private static func image(_ svg: String) -> NSImage? {
        if let hit = cache[svg] { return hit }
        guard let img = NSImage(data: Data(svg.utf8)) else { return nil }
        img.isTemplate = false
        cache[svg] = img
        return img
    }
}

/// Icon well in the Client details: the tile plus Choose SVG… / Remove.
struct ClientIconWell: View {
    let model: TrayModel
    let client: Client

    var body: some View {
        HStack(spacing: 12) {
            ClientIcon(client: client, color: model.clientColor(client), size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Button("Choose SVG…") { choose() }
                if client.icon != nil { Button("Remove") { model.setIcon(client, nil) } }
            }
            .buttonStyle(.link)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.prompt = "Use as Icon"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let svg = try? String(contentsOf: url, encoding: .utf8) else { model.error = "That file isn't an SVG."; return }
        model.setIcon(client, svg)
    }
}
