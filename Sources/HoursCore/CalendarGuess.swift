import Foundation

/// The calendar event current when a call starts, as the shell reports it.
struct CalendarEvent: Equatable {
    var title: String
    var attendeeEmails: [String]
}

extension Tracker {
    /// Guess order (spec): (1) an attendee's email domain matches a Client's domains -> that Client's
    /// most recently used Open Project; (2) a Project keyword appears in the event title; nil otherwise
    /// (the caller falls back to the last-used Project). Closed Projects are never returned; neither is
    /// `runningProjectId` (a call on it needs no switch).
    /// Defaults (spec is silent): a Project's keyword is its name; matching is case-insensitive and
    /// the longest matching name wins (ties: most recently used). Subdomains of a Client domain match.
    func calendarGuess(_ event: CalendarEvent, excluding runningProjectId: Int64?) throws -> Int64? {
        let candidates = try quickStartProjects(limit: .max).filter { $0.id != runningProjectId } // recent first
        let attendeeDomains = Set(event.attendeeEmails.compactMap {
            $0.split(separator: "@").last.map { $0.lowercased() }
        })
        if !attendeeDomains.isEmpty {
            var clientOfDomain: [String: Set<Int64>] = [:]
            for c in try clients() {
                for d in try domains(clientId: c.id!) { clientOfDomain[d, default: []].insert(c.id!) }
            }
            let matched = Set(attendeeDomains.flatMap { a in
                clientOfDomain.filter { a == $0.key || a.hasSuffix("." + $0.key) }.flatMap(\.value)
            })
            if let p = candidates.first(where: { matched.contains($0.clientId) }) { return p.id }
        }
        let title = event.title.lowercased()
        // max(by:) keeps the first of equals, so recency breaks ties.
        return candidates
            .filter { title.contains($0.name.lowercased()) }
            .max { $0.name.count < $1.name.count }?.id
    }
}
