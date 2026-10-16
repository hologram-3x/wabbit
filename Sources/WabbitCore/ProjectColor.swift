import Foundation
import GRDB

/// Fixed palette for the colour dot next to a Project name.
public enum ProjectColor: String, CaseIterable, Sendable, Codable {
    case red, orange, yellow, green, blue, purple, gray
}

func registerColorMigration(_ m: inout DatabaseMigrator) {
    m.registerMigration("v10-project-color") { db in
        try db.alter(table: "project") { $0.add(column: "color", .text) }
        let all = ProjectColor.allCases
        for (i, id) in try Int64.fetchAll(db, sql: "SELECT id FROM project ORDER BY id").enumerated() {
            try db.execute(sql: "UPDATE project SET color = ? WHERE id = ?", arguments: [all[i % all.count].rawValue, id])
        }
    }
    m.registerMigration("v11-hourly-by-default") { db in
        try db.execute(sql: "UPDATE project SET billingKind = 'hourly' WHERE billingKind IS NULL")
    }
}

extension Tracker {
    /// Random pick among the palette colours used by the fewest Projects.
    static func pickColor(_ db: Database) throws -> ProjectColor {
        let counts = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT color, COUNT(*) n FROM project WHERE color IS NOT NULL GROUP BY color").map { ($0["color"] as String, $0["n"] as Int) })
        let least = ProjectColor.allCases.map { counts[$0.rawValue] ?? 0 }.min()!
        return ProjectColor.allCases.filter { (counts[$0.rawValue] ?? 0) == least }.randomElement()!
    }

    public func setColor(projectId: Int64, _ color: ProjectColor) throws {
        try db.write { try $0.execute(sql: "UPDATE project SET color = ? WHERE id = ?", arguments: [color.rawValue, projectId]) }
    }
}
