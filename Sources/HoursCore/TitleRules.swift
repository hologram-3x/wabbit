import Foundation
import GRDB

public enum TitleRuleError: Error, Equatable { case emptyPattern, invalidPattern }

/// "Window title matches X → Project Y", for one Watched App. Evaluated in `position` order.
public struct TitleRule: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "titleRule"
    public enum Kind: String, Codable, Sendable { case contains, pattern }

    public var id: Int64?
    public var bundleID: String
    public var position: Int
    public var kind: Kind
    public var text: String
    public var projectId: Int64

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// "contains" is case-insensitive; "pattern" is a regular expression searched anywhere in the title.
    public func matches(_ title: String) -> Bool {
        switch kind {
        case .contains: return title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .pattern: return Self.regex(text)?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
        }
    }

    static func regex(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
}

extension Tracker {
    static func migrateTitleRules(_ db: Database) throws {
        try db.create(table: "titleRule", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("bundleID", .text).notNull().references("watchedApp", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("kind", .text).notNull()
            t.column("text", .text).notNull()
            t.belongsTo("project", onDelete: .cascade).notNull()
        }
    }

    public func titleRules(bundleID: String) throws -> [TitleRule] {
        try db.read { try TitleRule.filter(Column("bundleID") == bundleID).order(Column("position"), Column("id")).fetchAll($0) }
    }

    /// Appends a rule after the app's existing ones.
    @discardableResult
    public func addTitleRule(bundleID: String, kind: TitleRule.Kind, text: String, projectId: Int64) throws -> TitleRule {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw TitleRuleError.emptyPattern }
        if kind == .pattern, TitleRule.regex(text) == nil { throw TitleRuleError.invalidPattern }
        return try db.write { db in
            try Self.requireOpen(db, projectId: projectId)
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM titleRule WHERE bundleID = ?",
                                        arguments: [bundleID]) ?? 0
            var rule = TitleRule(id: nil, bundleID: bundleID, position: next, kind: kind, text: text, projectId: projectId)
            try rule.insert(db)
            return rule
        }
    }

    public func removeTitleRule(id: Int64) throws { try db.write { _ = try TitleRule.deleteOne($0, key: id) } }

    /// Reorders one app's rules to match `ids` (rules not listed keep their relative order, after).
    public func setTitleRuleOrder(bundleID: String, ids: [Int64]) throws {
        try db.write { db in
            let rest = try TitleRule.filter(Column("bundleID") == bundleID).order(Column("position"), Column("id"))
                .fetchAll(db).compactMap(\.id).filter { !ids.contains($0) }
            for (i, id) in (ids + rest).enumerated() {
                try db.execute(sql: "UPDATE titleRule SET position = ? WHERE id = ? AND bundleID = ?", arguments: [i, id, bundleID])
            }
        }
    }

    /// First rule (in order) matching `title` whose Project is Open, else the app's default Project.
    /// A nil title (no Accessibility permission, no window) skips the rules.
    func resolveProject(for app: WatchedApp, title: String?) -> Int64? {
        let rules = title == nil ? [] : ((try? titleRules(bundleID: app.bundleID)) ?? [])
        let candidates = rules.filter { $0.matches(title!) }.map(\.projectId) + [app.projectId].compactMap { $0 }
        return candidates.first { pid in (try? db.read { try Project.fetchOne($0, key: pid) }).flatMap { try? isClosed($0) } == false }
    }
}
