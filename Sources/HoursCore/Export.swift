import Foundation
import GRDB

/// Precise keeps exact durations; Rounded applies only in the Export (never to stored Sessions).
public enum ExportMode: String, Equatable, Sendable {
    case precise
    case rounded
}

/// Scope for a CSV Export: one Project, one Client, or a date range (by Session start).
public enum ExportScope: Equatable, Sendable {
    case project(Int64)
    case client(Int64)
    case dateRange(Range<Date>)
}

public enum ExportRounding {
    public static let defaultStep: TimeInterval = 3600
    public static let defaultThreshold: TimeInterval = 15 * 60

    /// Per Session: remainder beyond whole steps ≤ threshold → round down; else up.
    public static func roundDuration(
        seconds: TimeInterval,
        step: TimeInterval = defaultStep,
        threshold: TimeInterval = defaultThreshold
    ) -> TimeInterval {
        let stepSec = max(1, Int(step.rounded()))
        let threshSec = max(0, Int(threshold.rounded()))
        let total = max(0, Int(seconds.rounded()))
        let whole = (total / stepSec) * stepSec
        let remainder = total - whole
        return TimeInterval(remainder <= threshSec ? whole : whole + stepSec)
    }
}

func registerExportMigration(_ m: inout DatabaseMigrator) {
    m.registerMigration("v5-export") { db in
        try db.create(table: "setting", ifNotExists: true) { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }
        try db.execute(
            sql: "INSERT OR IGNORE INTO setting (key, value) VALUES (?, ?)",
            arguments: ["roundStepSeconds", String(Int(ExportRounding.defaultStep))]
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO setting (key, value) VALUES (?, ?)",
            arguments: ["roundThresholdSeconds", String(Int(ExportRounding.defaultThreshold))]
        )
    }
}

extension Tracker {
    // MARK: Rounding settings (defaults: step 1 h, threshold 15 min)

    public func roundingStep() throws -> TimeInterval {
        try db.read {
            try Self.setting($0, "roundStepSeconds").flatMap(TimeInterval.init)
                ?? ExportRounding.defaultStep
        }
    }

    public func setRoundingStep(_ seconds: TimeInterval) throws {
        guard seconds > 0 else { throw HoursError.invalidMoney }
        try db.write { try Self.setSetting($0, "roundStepSeconds", String(Int(seconds.rounded()))) }
    }

    public func roundingThreshold() throws -> TimeInterval {
        try db.read {
            try Self.setting($0, "roundThresholdSeconds").flatMap(TimeInterval.init)
                ?? ExportRounding.defaultThreshold
        }
    }

    public func setRoundingThreshold(_ seconds: TimeInterval) throws {
        guard seconds >= 0 else { throw HoursError.invalidMoney }
        try db.write { try Self.setSetting($0, "roundThresholdSeconds", String(Int(seconds.rounded()))) }
    }

    // MARK: Export

    /// CSV of Sessions for the scope. Sessions stay precise in storage; rounding is only in the returned text.
    /// Columns: date, client, project, start, end, duration, rate, amount, manual.
    /// `manual` is always false until Manual Sessions (ticket 04) land.
    public func exportCSV(scope: ExportScope, mode: ExportMode) throws -> String {
        let now = clock.now()
        let step = try roundingStep()
        let threshold = try roundingThreshold()
        let rows = try db.read { db -> [String] in
            let clients = Dictionary(uniqueKeysWithValues: try Client.fetchAll(db).map { ($0.id!, $0) })
            let projects = Dictionary(uniqueKeysWithValues: try Project.fetchAll(db).map { ($0.id!, $0) })
            var sessions = try Session.order(Column("start")).fetchAll(db)
            sessions = sessions.filter { session in
                switch scope {
                case .project(let id): return session.projectId == id
                case .client(let id):
                    return projects[session.projectId]?.clientId == id
                case .dateRange(let range):
                    return range.contains(session.start)
                }
            }
            return try sessions.map { session in
                let project = projects[session.projectId]!
                let client = clients[project.clientId]!
                let end = session.end ?? now
                let exact = end.timeIntervalSince(session.start)
                let billed = mode == .rounded
                    ? ExportRounding.roundDuration(seconds: exact, step: step, threshold: threshold)
                    : exact
                let rate = try Self.money(db, projectId: project.id!).rateCents ?? 0
                let amount = Money.revenue(seconds: billed, rateCents: rate)
                // "false" until ticket 04 adds a Manual flag on Session.
                return [
                    Self.csvDay(session.start),
                    Self.csvEscape(client.name),
                    Self.csvEscape(project.name),
                    Self.csvInstant(session.start),
                    Self.csvInstant(end),
                    Self.csvDurationHours(billed),
                    Self.csvCents(rate),
                    Self.csvCents(amount),
                    "false",
                ].joined(separator: ",")
            }
        }
        let header = "date,client,project,start,end,duration,rate,amount,manual"
        // UTF-8 BOM so Excel on Windows recognises encoding; Numbers is fine with it too.
        return "\u{FEFF}" + ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func csvDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let p = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    private static func csvInstant(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }
    private static func csvDurationHours(_ seconds: TimeInterval) -> String {
        String(format: "%.4f", seconds / 3600)
    }
    private static func csvCents(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100)
    }
    private static func csvEscape(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
