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
    /// Newest folder signal (normalised, lowercased) and when it came; see FolderSignals.swift.
    var signal: (path: String, at: Date)?
    /// Front browser tab's address (normalised), from `.browserAddress`; cleared when the app changes.
    var address: (host: String, path: String)?
    var since = Date.distantPast
    /// "Not now": per app, for `notNowDuration`.
    var notNowUntil: [String: Date] = [:]
    /// "Not today": per app, until local midnight.
    var notToday: [String: Date] = [:]
    /// The app that was in front just before, so a quick alt-tab back keeps the dwell time.
    var away: (bundleID: String, since: Date, leftAt: Date)?
}

extension Tracker {
    static let watchedDelayKey = "watchedAppDelaySeconds"
    public static let watchedDelayRange: ClosedRange<TimeInterval> = 5...600
    public static let watchedDelayDefault: TimeInterval = 30
    public static let notNowDuration: TimeInterval = 3600

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
              (w.notNowUntil[id] ?? .distantPast) <= now,
              workingHours().contains(now),
              (w.notToday[id] ?? .distantPast) <= now,
              let app = try? db.read({ try WatchedApp.fetchOne($0, key: id) })
        else { return nil }
        // Fresh folder signal (terminals only), then browser address, then document folder, then title rules,
        // then the default; a Closed Project is no suggestion.
        let matched = freshFolderSignal(frontApp: id).flatMap(projectForNormalised)
            ?? w.address.flatMap(projectForNormalisedAddress)
            ?? w.document.flatMap(projectForNormalised) ?? resolveProject(for: app, title: w.title)
        let runningId = (try? runningSession())?.projectId
        if let matched {
            guard runningId != matched else { return nil }
        } else if runningId != nil {
            return nil
        }
        return WatchedAppPrompt(bundleID: id, appName: app.name, projectId: matched)
    }

    /// "Not now": quiet for this app for an hour, however often the user switches away and back.
    public func snoozeWatchedAppNotNow() {
        guard let id = watched.front else { return }
        watched.notNowUntil[id] = clock.now().addingTimeInterval(Self.notNowDuration)
    }

    /// When a prompt for the front app that is held back by a snooze or by working hours may come back;
    /// the shell schedules one check then. Nil when nothing is holding it.
    public func watchedPromptResumeAt() -> Date? {
        guard let id = watched.front else { return nil }
        let now = clock.now()
        let wh = workingHours()
        let ends = [watched.notNowUntil[id], watched.notToday[id], wh.contains(now) ? nil : wh.nextOpen(after: now)]
        return ends.compactMap { $0 }.filter { $0 > now }.max()
    }

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
        w.address = nil
        let delay = (try? watchedAppDelay()) ?? Self.watchedDelayDefault
        let resume = w.away.flatMap { $0.bundleID == id && now.timeIntervalSince($0.leftAt) < delay ? $0 : nil }
        // Only watched apps are remembered, so hopping through unwatched apps keeps the last stay.
        if let old = w.front, (try? db.read { try WatchedApp.fetchOne($0, key: old) }) != nil {
            w.away = (old, w.since, now)
        }
        if let resume {
            // Quick alt-tab back: same stay, so no new prompt cycle.
            w.since = resume.since
        } else {
            w.since = now
        }
        w.front = id
    }
}

/// When Watched App prompts may appear. Off = always. Meeting and Idle prompts ignore it.
/// `end <= start` runs overnight (22:00-02:00). Weekdays use `Calendar` numbering (1 = Sunday).
public struct WorkingHours: Equatable, Sendable {
    public var enabled = false
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public var startMinute = 9 * 60
    public var endMinute = 18 * 60

    public init(enabled: Bool = false, weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 540, endMinute: Int = 1080) {
        self.enabled = enabled; self.weekdays = weekdays; self.startMinute = startMinute; self.endMinute = endMinute
    }

    public func contains(_ date: Date, calendar cal: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let m = c.hour! * 60 + c.minute!, day = c.weekday!
        if startMinute < endMinute { return weekdays.contains(day) && m >= startMinute && m < endMinute }
        // Overnight: the evening belongs to its own day, the small hours to the day before.
        return (weekdays.contains(day) && m >= startMinute) || (weekdays.contains(day == 1 ? 7 : day - 1) && m < endMinute)
    }

    /// The next start time on a selected weekday after `date` (a window opens only at a start time).
    public func nextOpen(after date: Date, calendar cal: Calendar = .current) -> Date? {
        guard enabled, !weekdays.isEmpty else { return nil }
        let day0 = cal.startOfDay(for: date)
        for i in 0...7 {
            guard let day = cal.date(byAdding: .day, value: i, to: day0),
                  weekdays.contains(cal.component(.weekday, from: day)),
                  let t = cal.date(byAdding: .minute, value: startMinute, to: day), t > date else { continue }
            return t
        }
        return nil
    }
}

extension Tracker {
    static let workingHoursKey = "watchedWorkingHours"

    public func workingHours() -> WorkingHours {
        // Stored as "on|2,3,4|540|1080".
        guard let raw = try? db.read({ try Self.setting($0, Self.workingHoursKey) }) else { return WorkingHours() }
        let p = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard p.count == 4, let s = Int(p[2]), let e = Int(p[3]) else { return WorkingHours() }
        return WorkingHours(enabled: p[0] == "1", weekdays: Set(p[1].split(separator: ",").compactMap { Int($0) }),
                            startMinute: s, endMinute: e)
    }

    public func setWorkingHours(_ w: WorkingHours) throws {
        let days = w.weekdays.sorted().map(String.init).joined(separator: ",")
        try db.write { try Self.setSetting($0, Self.workingHoursKey, "\(w.enabled ? 1 : 0)|\(days)|\(w.startMinute)|\(w.endMinute)") }
    }
}
