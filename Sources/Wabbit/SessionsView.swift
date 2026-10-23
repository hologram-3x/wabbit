import WabbitCore
import SwiftUI

/// Sessions in a sortable table, filterable by Project, with add/edit/delete. Added Sessions are marked Manual.
struct SessionsView: View {
    let model: TrayModel
    @State private var sessions: [Session] = []
    @State private var filter: Int64?
    @State private var sortOrder = [KeyPathComparator(\Row.start, order: .reverse)]
    @State private var selection = Set<Int64>()
    @State private var editing: Session?
    @State private var adding = false
    @State private var error: String?

    private struct Row: Identifiable {
        let s: Session
        let project: String
        let hours: Double
        var id: Int64 { s.id! }
        var start: Date { s.start }
        var end: Date { s.end ?? .distantFuture }
    }

    private var rows: [Row] {
        sessions.filter { filter == nil || $0.projectId == filter }
            .map { Row(s: $0, project: model.label(forAny: $0.projectId), hours: model.tracker.duration(of: $0) / 3600) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.start) { Text($0.start.formatted(date: .abbreviated, time: .omitted)) }
            TableColumn("Start") { Text($0.start.formatted(date: .omitted, time: .shortened)) }
            TableColumn("End", value: \.end) { Text($0.s.end?.formatted(date: .omitted, time: .shortened) ?? "running") }
            TableColumn("Duration", value: \.hours) {
                Text(String(format: "%.2f h", $0.hours)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            TableColumn("Project", value: \.project) { r in
                HStack(spacing: 6) { ProjectDot(color: model.color(for: r.s.projectId)); Text(r.project) }
            }
            TableColumn("Manual") { r in
                if r.s.manual { Image(systemName: "hand.raised").help("Added by hand").accessibilityLabel("Manual") }
            }
            .width(56)
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let s = finished(ids), ids.count == 1 { Button("Edit…") { editing = s } }
            if finished(ids) != nil { Button("Delete", role: .destructive) { delete(ids) } }
        } primaryAction: { ids in
            if ids.count == 1 { editing = finished(ids) }
        }
        .onDeleteCommand { delete(selection) }
        .toolbar {
            ToolbarItem {
                Picker("Project", selection: $filter) {
                    Text("All Projects").tag(Int64?.none)
                    ForEach(model.allProjects) { Text(model.label(forAny: $0.id!)).tag(Int64?.some($0.id!)) }
                }
            }
            if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
            ToolbarItem {
                Button("Add Session", systemImage: "plus") { adding = true }
                    .disabled(model.projects.isEmpty).primaryToolbarButton()
            }
        }
        .errorAlert($error)
        .onAppear { model.refresh(); load() }
        .sheet(item: $editing) { s in
            SessionEditor(model: model, session: s) { editing = nil; load() }
        }
        .sheet(isPresented: $adding) {
            SessionEditor(model: model, session: nil) { adding = false; load() }
        }
    }

    /// The first selected Session if all are finished (a running Session can't be edited or deleted here).
    private func finished(_ ids: Set<Int64>) -> Session? {
        let picked = sessions.filter { ids.contains($0.id!) }
        return picked.allSatisfy { $0.end != nil } ? picked.first : nil
    }

    private func delete(_ ids: Set<Int64>) {
        guard finished(ids) != nil else { return }
        do { for id in ids { try model.tracker.deleteSession(id: id) } } catch { self.error = SessionsView.message(error) }
        selection = []
        load()
    }

    /// End at or before start means the Session crosses midnight; it still belongs to `day`.
    static func combine(day: Date, start: Date, end: Date) -> (Date, Date) {
        let cal = Calendar.current
        func on(_ t: Date, _ d: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: t)
            return cal.date(bySettingHour: c.hour!, minute: c.minute!, second: 0, of: d)!
        }
        let s = on(start, day)
        var e = on(end, day)
        if e <= s { e = cal.date(byAdding: .day, value: 1, to: e)! }
        return (s, e)
    }

    static func message(_ error: Error) -> String {
        if case WabbitError.sessionOverlap(_, let label) = error { return "Overlaps another Session: \(label)" }
        return "\(error)"
    }

    private func load() { sessions = (try? model.tracker.allSessions()) ?? [] }
}

/// Edits a Session, or adds a Manual one when `session` is nil (defaults to yesterday 09:00-11:00).
private struct SessionEditor: View {
    let model: TrayModel
    let session: Session?
    let done: () -> Void
    @State private var projectId: Int64?
    @State private var start = Date()
    @State private var end = Date()
    @State private var day = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    @State private var error: String?

    var body: some View {
        Form {
            Picker("Project", selection: $projectId) {
                ForEach(model.projects) { Text(model.label(for: $0.id!)).tag(Optional($0.id!)) }
            }
            if session == nil {
                DatePicker("Date", selection: $day, displayedComponents: .date)
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
            } else {
                DatePicker("Start", selection: $start)
                DatePicker("End", selection: $end)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .formSheet(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done).keyboardShortcut(.cancelAction) }
            ToolbarItem(placement: .confirmationAction) {
                Button(session == nil ? "Add" : "Save", action: save).keyboardShortcut(.defaultAction).disabled(projectId == nil)
            }
        }
        .onAppear {
            if let session {
                projectId = session.projectId; start = session.start; end = session.end ?? .now
            } else {
                projectId = model.projects.first?.id
                start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
                end = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: .now)!
            }
        }
    }

    private func save() {
        guard let projectId else { return }
        do {
            if let session {
                try model.tracker.editSession(id: session.id!, projectId: projectId, start: start, end: end)
            } else {
                let (s, e) = SessionsView.combine(day: day, start: start, end: end)
                try model.tracker.addManualSession(projectId: projectId, start: s, end: e)
            }
            done()
        } catch { self.error = SessionsView.message(error) }
    }
}
