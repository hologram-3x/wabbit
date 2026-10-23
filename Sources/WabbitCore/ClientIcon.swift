import Foundation
import GRDB

public enum ClientIconError: Error, Equatable {
    case tooLarge, notSVG
}

extension Tracker {
    /// SVG text larger than this (UTF-8 bytes) is refused.
    public static let maxIconBytes = 256 * 1024

    /// Sets the Client's custom icon to `svg`, or clears it with nil. Stored in the database, so backups carry it.
    public func setIcon(clientId: Int64, svg: String?) throws {
        if let svg {
            guard svg.utf8.count <= Self.maxIconBytes else { throw ClientIconError.tooLarge }
            guard svg.range(of: "<svg", options: .caseInsensitive) != nil else { throw ClientIconError.notSVG }
        }
        try db.write { db in
            guard try Client.exists(db, key: clientId) else { throw WabbitError.notFound }
            try db.execute(sql: "UPDATE client SET icon = ? WHERE id = ?", arguments: [svg, clientId])
        }
    }
}
