import Foundation
import GRDB

// Money is integer cents. Every amount is rounded to the cent exactly once, at the end of its formula.

public enum Billing: Equatable, Sendable {
    case hourly
    case fixed(priceCents: Int, estimatedHours: Double)
}

public enum AmountMode: String, Sendable { case gross, net }

public struct ProjectMoney: Equatable, Sendable {
    public var rateCents: Int?     // per hour
    public var billing: Billing?   // nil = no Billing: no warnings
    public init(rateCents: Int? = nil, billing: Billing? = nil) { self.rateCents = rateCents; self.billing = billing }
}

public enum Money {
    /// Integer division rounded half up (amounts are never negative).
    static func divRound(_ n: Int, _ d: Int) -> Int { (2 * n + d) / (2 * d) }

    /// Tax Rate is in basis points (22% = 2200), so no floating point reaches the cents.
    public static func net(ofGross cents: Int, taxBps: Int) -> Int { divRound(cents * (10_000 - taxBps), 10_000) }
    public static func gross(ofNet cents: Int, taxBps: Int) -> Int { divRound(cents * 10_000, 10_000 - taxBps) }

    /// Reads a revenue under the Net/Gross Switch: Gross -> revenue x (1 - tax), Net -> revenue / (1 - tax).
    public static func display(_ cents: Int, mode: AmountMode, taxBps: Int) -> Int {
        mode == .gross ? net(ofGross: cents, taxBps: taxBps) : gross(ofNet: cents, taxBps: taxBps)
    }

    /// Hourly revenue: seconds at a cents/hour Rate, rounded once.
    public static func revenue(seconds: Double, rateCents: Int) -> Int { Int((seconds * Double(rateCents) / 3600).rounded()) }

    /// Fixed price / hours tracked, in cents per hour. Nil with no time tracked.
    public static func effectiveRate(priceCents: Int, seconds: Double) -> Int? {
        seconds > 0 ? Int((Double(priceCents) * 3600 / seconds).rounded()) : nil
    }
}

public struct ProjectOverview: Equatable {
    public var project: Project
    public var closed: Bool
    public var seconds: Double            // in the date range
    public var revenueCents: Int          // raw, before the Net/Gross Switch
    public var effectiveRateCents: Int?   // Fixed only, over all tracked time
    public var rateCents: Int?
    public var percentOfEstimate: Double? // Fixed only, over all tracked time
    public var overEstimate: Bool
    public var underRate: Bool
    public var hasWarning: Bool { overEstimate || underRate }
}

public struct ClientOverview: Equatable {
    public var client: Client
    public var projects: [ProjectOverview]
    public var seconds: Double { projects.reduce(0) { $0 + $1.seconds } }
    public var revenueCents: Int { projects.reduce(0) { $0 + $1.revenueCents } }
}

func registerMoneyMigration(_ m: inout DatabaseMigrator) {
    m.registerMigration("v3-money") { db in
        try db.alter(table: "project") { t in
            t.add(column: "rateCents", .integer)
            t.add(column: "billingKind", .text)  // NULL, "hourly" or "fixed"
            t.add(column: "fixedPriceCents", .integer)
            t.add(column: "estimatedHours", .double)
        }
        try db.create(table: "setting", ifNotExists: true) { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }
    }
}

extension Tracker {
    // MARK: Settings (defaults: Tax Rate 0, Gross)

    public func taxRateBps() throws -> Int {
        try db.read { try Self.setting($0, "taxBps").flatMap(Int.init) ?? 0 }
    }

    /// Basis points, 0..<10000.
    public func setTaxRateBps(_ bps: Int) throws {
        guard (0..<10_000).contains(bps) else { throw HoursError.invalidMoney }
        try db.write { try Self.setSetting($0, "taxBps", String(bps)) }
    }

    public func amountMode() throws -> AmountMode {
        try db.read { try Self.setting($0, "amountMode").flatMap(AmountMode.init) ?? .gross }
    }

    public func setAmountMode(_ mode: AmountMode) throws {
        try db.write { try Self.setSetting($0, "amountMode", mode.rawValue) }
    }

    /// The freelancer's own hourly rate; new Projects start from it. Nil when unset.
    public func defaultRateCents() throws -> Int? {
        try db.read { try Self.setting($0, "defaultRateCents").flatMap(Int.init) }
    }

    /// Nil removes the setting. Existing Projects are never changed.
    public func setDefaultRateCents(_ cents: Int?) throws {
        if let c = cents, c < 0 { throw HoursError.invalidMoney }
        try db.write {
            if let c = cents { try Self.setSetting($0, "defaultRateCents", String(c)) }
            else { try $0.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: ["defaultRateCents"]) }
        }
    }

    /// A new Project inherits the Default Rate, if set.
    static func applyDefaultRate(_ db: Database, to project: Project) throws {
        guard let r = try setting(db, "defaultRateCents").flatMap(Int.init) else { return }
        try db.execute(sql: "UPDATE project SET rateCents = ? WHERE id = ?", arguments: [r, project.id!])
    }

    static func setting(_ db: Database, _ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key])
    }

    static func setSetting(_ db: Database, _ key: String, _ value: String) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", arguments: [key, value])
    }

    // MARK: Rate and Billing per Project

    public func setMoney(projectId: Int64, _ money: ProjectMoney) throws {
        if let r = money.rateCents, r < 0 { throw HoursError.invalidMoney }
        var kind: String?, price: Int?, hours: Double?
        switch money.billing {
        case nil: break
        case .hourly: kind = "hourly"
        case let .fixed(p, h):
            guard p >= 0, h > 0 else { throw HoursError.invalidMoney }
            kind = "fixed"; price = p; hours = h
        }
        try db.write { db in
            try db.execute(sql: "UPDATE project SET rateCents = ?, billingKind = ?, fixedPriceCents = ?, estimatedHours = ? WHERE id = ?",
                           arguments: [money.rateCents, kind, price, hours, projectId])
        }
    }

    public func money(projectId: Int64) throws -> ProjectMoney {
        try db.read { try Self.money($0, projectId: projectId) }
    }

    static func money(_ db: Database, projectId: Int64) throws -> ProjectMoney {
        guard let row = try Row.fetchOne(db, sql: "SELECT rateCents, billingKind, fixedPriceCents, estimatedHours FROM project WHERE id = ?", arguments: [projectId]) else {
            throw HoursError.notFound
        }
        let billing: Billing? = switch row["billingKind"] as String? {
        case "hourly": .hourly
        case "fixed": .fixed(priceCents: row["fixedPriceCents"] ?? 0, estimatedHours: row["estimatedHours"] ?? 0)
        default: nil
        }
        return ProjectMoney(rateCents: row["rateCents"], billing: billing)
    }

    // MARK: Overview

    /// Per Client and Project, Closed ones included. Sessions count when they start in `range` (nil = all time);
    /// a running Session counts up to now.
    /// Defaults: a Fixed price is spread over the range pro rata to hours (so Client totals add up), while
    /// Effective Rate and % of estimate use all tracked time, since the price covers the whole Project.
    public func overview(range: Range<Date>? = nil) throws -> [ClientOverview] {
        let now = clock.now()
        return try db.read { db in
            let sessions = try Session.fetchAll(db)
            func secs(_ s: [Session]) -> Double { s.reduce(0) { $0 + ($1.end ?? now).timeIntervalSince($1.start) } }
            let projects = try Project.order(Column("name")).fetchAll(db)
            return try Client.order(Column("name")).fetchAll(db).map { client in
                let rows = try projects.filter { $0.clientId == client.id }.map { p -> ProjectOverview in
                    let all = sessions.filter { $0.projectId == p.id }
                    let inRange = range.map { r in all.filter { r.contains($0.start) } } ?? all
                    let total = secs(all), part = secs(inRange)
                    let m = try Self.money(db, projectId: p.id!)
                    var o = ProjectOverview(project: p, closed: p.closedAt != nil || client.closedAt != nil, seconds: part,
                                            revenueCents: 0, rateCents: m.rateCents, overEstimate: false, underRate: false)
                    switch m.billing {
                    case .hourly:
                        o.revenueCents = Money.revenue(seconds: part, rateCents: m.rateCents ?? 0)
                    case let .fixed(price, est):
                        o.revenueCents = total > 0 ? Int((Double(price) * part / total).rounded()) : 0
                        o.effectiveRateCents = Money.effectiveRate(priceCents: price, seconds: total)
                        o.percentOfEstimate = total / 3600 / est * 100
                        o.overEstimate = total / 3600 > est
                        if let eff = o.effectiveRateCents, let rate = m.rateCents { o.underRate = eff < rate }
                    case nil:
                        o.revenueCents = Money.revenue(seconds: part, rateCents: m.rateCents ?? 0)
                    }
                    return o
                }
                return ClientOverview(client: client, projects: rows)
            }
        }
    }
}
