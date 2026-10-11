import HoursCore
import SwiftUI

/// Sessions grouped per day or per Project, with add/edit/delete. Added Sessions are marked Manual.
struct SessionsView: View {
    let model: TrayModel
    @State private var sessions: [Session] = []
    @State private var byProject = false
    @State private var editing: Session?
    @State private var error: String?
    // Add form. Defaults to yesterday 09:00-11:00: pick a Project, press Add.
    @State private var projectId: Int64?
    @State private var day = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    @State private var endTime = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: .now)!

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Project", selection: $projectId) {
                    ForEach(model.projects) { Text(model.label(for: $0.id!)).tag(Optional($0.id!)) }
                }.frame(maxWidth: 260)
                DatePicker("", selection: $day, displayedComponents: .date).labelsHidden()
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute).labelsHidden()
                DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute).labelsHidden()
                Button("Add") { add() }.disabled(projectId == nil).keyboardShortcut(.defaultAction)
            }
            Picker("Group by", selection: $byProject) {
                Text("Day").tag(false)
                Text("Project").tag(true)
            }.pickerStyle(.segmented).frame(width: 200)
            List {
                ForEach(groups, id: \.title) { g in
                    Section(g.title) { ForEach(g.sessions) { row($0) } }
                }
            }
            if let e = error ?? model.error { Text(e).foregroundStyle(.red) }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { model.refresh(); projectId = projectId ?? model.projects.first?.id; load() }
        .sheet(item: $editing) { s in
            SessionEditor(model: model, session: s) { editing = nil; load() }
        }
    }

    private var groups: [(title: String, sessions: [Session])] {
        if byProject {
            Dictionary(grouping: sessions, by: \.projectId)
                .map { (model.label(forAny: $0.key), $0.value) }.sorted { $0.0 < $1.0 }
        } else {
            Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.start) }
                .sorted { $0.key > $1.key }.map { ($0.key.formatted(date: .complete, time: .omitted), $0.value) }
        }
    }

    private func row(_ s: Session) -> some View {
        HStack {
            Text(s.start.formatted(date: byProject ? .abbreviated : .omitted, time: .shortened)
                + " – " + (s.end?.formatted(date: .omitted, time: .shortened) ?? "running"))
            if !byProject { Text(model.label(forAny: s.projectId)).foregroundStyle(.secondary) }
            if s.manual { Text("Manual").font(.caption).padding(.horizontal, 4).background(.quaternary, in: Capsule()) }
            Spacer()
            Text(String(format: "%.2f h", model.tracker.duration(of: s) / 3600)).monospacedDigit()
            if s.end != nil {
                Button("Edit") { editing = s }
                Button("Delete", role: .destructive) { run { try model.tracker.deleteSession(id: s.id!) } }
            }
        }
    }

    private func add() {
        guard let projectId else { return }
        let (s, e) = Self.combine(day: day, start: startTime, end: endTime)
        run { try model.tracker.addManualSession(projectId: projectId, start: s, end: e) }
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

    private func run(_ body: () throws -> Void) {
        do { try body(); error = nil } catch { self.error = SessionsView.message(error) }
        load()
    }

    static func message(_ error: Error) -> String {
        if case HoursError.sessionOverlap(_, let label) = error { return "Overlaps another Session: \(label)" }
        return "\(error)"
    }

    private func load() { sessions = (try? model.tracker.allSessions()) ?? [] }
}

private struct SessionEditor: View {
    let model: TrayModel
    let session: Session
    let done: () -> Void
    @State private var projectId: Int64?
    @State private var start = Date()
    @State private var end = Date()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Project", selection: $projectId) {
                ForEach(model.projects) { Text(model.label(for: $0.id!)).tag(Optional($0.id!)) }
            }
            DatePicker("Start", selection: $start)
            DatePicker("End", selection: $end)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try model.tracker.editSession(id: session.id!, projectId: projectId ?? session.projectId, start: start, end: end)
                        done()
                    } catch { self.error = SessionsView.message(error) }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding().frame(width: 420)
        .onAppear { projectId = session.projectId; start = session.start; end = session.end ?? .now }
    }
}
