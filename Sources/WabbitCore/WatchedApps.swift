import Foundation
import GRDB

/// A Watched App, identified by bundle identifier, with an optional default Project.
public struct WatchedApp: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var bundleID: String
    public var name: String
    public var projectId: Int64?

    public init(bundleID: String, name: String, projectId: Int64?) {
        self.bundleID = bundleID; self.name = name; self.projectId = projectId
    }
}

/// "Start tracking?" suggestion for the app in front. `projectId` is nil when the app has no usable default.
public struct WatchedAppPrompt: Equatable, Sendable {
    public let bundleID: String
    public let appName: String
    public let projectId: Int64?

    public init(bundleID: String, appName: String, projectId: Int64?) {
        self.bundleID = bundleID; self.appName = appName; self.projectId = projectId
    }
}

/// In-memory front-app observation and snoozes. Not persisted (a relaunch starts clean).
final class WatchedAppRuntime {
    var front: String?
    /// Focused window title of the front app, nil when unknown (no Accessibility permission).
    var title: String?
    /// Focused window's document path, normalised and lowercased; nil when none or unknown.
    var document: String?
    var since = Date.distantPast
    /// "Not now": until the app leaves the front.
    var notNow = false
    /// "Not today": per app, until local midnight.
    var notToday: [String: Date] = [:]
    /// The app that was in front just before, so a quick alt-tab back keeps the dwell time and snoozes.
    var away: (bundleID: String, since: Date, leftAt: Date, notNow: Bool)?
}

extension Tracker {
    static let watchedDelayKey = "watchedAppDelaySeconds"
    public static let watchedDelayRange: ClosedRange<TimeInterval> = 5...600
    public static let watchedDelayDefault: TimeInterval = 30

    static func migrateWatchedApps(_ db: Database) throws {
        try db.create(table: "watchedApp", ifNotExists: true) { t in
            t.column("bundleID", .text).primaryKey()
            t.column("name", .text).notNull()
            t.belongsTo("project", onDelete: .setNull)
        }
    }

    // MARK: Configuration

    public func watchedApps() throws -> [WatchedApp] {
        try db.read { try WatchedApp.order(Column("name")).fetchAll($0) }
    }

    /// Adds or updates a Watched App (its default Project may be nil).
    public func setWatchedApp(bundleID: String, name: String, projectId: Int64?) throws {
        try db.write { db in
            if let projectId { try Self.requireOpen(db, projectId: projectId) }
            try WatchedApp(bundleID: bundleID, name: name, projectId: projectId).save(db)
        }
    }

    public func removeWatchedApp(bundleID: String) throws {
        try db.write { _ = try WatchedApp.deleteOne($0, key: bundleID) }
    }

    public func watchedAppDelay() throws -> TimeInterval {
        let raw = try db.read {
            try String.fetchOne($0, sql: "SELECT value FROM setting WHERE key = ?", arguments: [Self.watchedDelayKey])
        }
        let seconds = raw.flatMap(TimeInterval.init(_:)) ?? Self.watchedDelayDefault
        return min(max(seconds, Self.watchedDelayRange.lowerBound), Self.watchedDelayRange.upperBound)
    }

    public func setWatchedAppDelay(_ seconds: TimeInterval) throws {
        let clamped = min(max(seconds, Self.watchedDelayRange.lowerBound), Self.watchedDelayRange.upperBound)
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO setting (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.watchedDelayKey, String(Int(clamped.rounded()))]
            )
        }
    }

    // MARK: Prompt

    /// The prompt due right now, if any. Computed from the clock, so the shell only has to ask again
    /// once the delay has passed (no polling in the core).
    public func pendingWatchedAppPrompt() -> WatchedAppPrompt? {
        let w = watched
        let now = clock.now()
        guard let id = w.front,
              now.timeIntervalSince(w.since) >= ((try? watchedAppDelay()) ?? Self.watchedDelayDefault),
              !w.notNow,
              (w.notToday[id] ?? .distantPast) <= now,
              let app = try? db.read({ try WatchedApp.fetchOne($0, key: id) })
        else { return nil }
        // Document folder first, then title rules, then the default; a Closed Project is no suggestion.
        let matched = w.document.flatMap(projectForNormalised) ?? resolveProject(for: app, title: w.title)
        let runningId = (try? runningSession())?.projectId
        if let matched {
            guard runningId != matched else { return nil }
        } else if runningId != nil {
            return nil
        }
        return WatchedAppPrompt(bundleID: id, appName: app.name, projectId: matched)
    }

    /// "Not now": quiet until the app leaves the front.
    public func snoozeWatchedAppNotNow() { watched.notNow = true }

    /// "Not today": quiet for this app until local midnight.
    public func snoozeWatchedAppNotToday() {
        guard let id = watched.front else { return }
        let now = clock.now()
        watched.notToday[id] = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime
        )
    }

    func handleWatchedAppEvent(_ event: DetectionEvent) {
        guard case .activeAppChanged(let id, let title, let document) = event else { return }
        let w = watched
        let now = clock.now()
        w.title = title
        w.document = document.map { Self.normalisedPath($0).lowercased() }
        guard id != w.front else { return } // same app, new window title: keeps the stay
        let delay = (try? watchedAppDelay()) ?? Self.watchedDelayDefault
        let resume = w.away.flatMap { $0.bundleID == id && now.timeIntervalSince($0.leftAt) < delay ? $0 : nil }
        // Only watched apps are remembered, so hopping through unwatched apps keeps the last stay.
        if let old = w.front, (try? db.read { try WatchedApp.fetchOne($0, key: old) }) != nil {
            w.away = (old, w.since, now, w.notNow)
        }
        if let resume {
            // Quick alt-tab back: same stay, so no new prompt cycle.
            w.since = resume.since
            w.notNow = resume.notNow
        } else {
            w.since = now
            w.notNow = false
        }
        w.front = id
    }
}
