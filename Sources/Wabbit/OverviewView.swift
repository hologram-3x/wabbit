import WabbitCore
import SwiftUI

/// Overview per Client and Project. Net/Gross and Tax Rate come from Config (via the model).
struct OverviewView: View {
    let model: TrayModel
    @State private var rows: [Row] = []
    @State private var selection: Row.ID?
    @State private var useRange = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var to = Date.now
    @State private var editing: Project?

    /// A Client (with its Projects as children) or a Project.
    private struct Row: Identifiable {
        let id: String
        let name: String
        let seconds: Double
        let revenueCents: Int
        var p: ProjectOverview?
        var children: [Row]?
    }

    var body: some View {
        Table(rows, children: \.children, selection: $selection) {
            TableColumn("Name") { r in
                HStack(spacing: 6) {
                    if let p = r.p { ProjectDot(color: p.project.color) }
                    cell(r, r.name)
                }
            }
            .width(min: 160, ideal: 240)
            TableColumn("Hours") { r in cell(r, hours(r.seconds), trailing: true) }
                .width(min: 50, ideal: 64)
            TableColumn("\(modeLabel) Revenue") { r in cell(r, euro(r.revenueCents), trailing: true) }
            TableColumn("\(modeLabel) Rate") { r in cell(r, r.p?.rateCents.map { euro($0, perHour: true) } ?? "", trailing: true) }
            TableColumn("\(modeLabel) Effective Rate") { r in cell(r, r.p?.effectiveRateCents.map { euro($0, perHour: true) } ?? "", trailing: true) }
            TableColumn("% of Estimate") { r in cell(r, r.p?.percentOfEstimate.map { "\(Int($0.rounded()))%" } ?? "", trailing: true) }
            TableColumn("Warnings") { r in
                HStack {
                    if r.p?.overEstimate == true { Label("Over estimate", systemImage: "exclamationmark.triangle.fill") }
                    if r.p?.underRate == true { Label("Under Rate", systemImage: "exclamationmark.triangle.fill") }
                }
                .foregroundStyle(.red)
            }
        }
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            if let p = project(ids) { Button("Rate & Billing…") { editing = p } }
        } primaryAction: { ids in editing = project(ids) }
        .navigationSubtitle("\(model.amountMode == .net ? "Net" : "Gross") · Tax \(String(format: "%g", Double(model.taxBps) / 100))%")
        .toolbar {
            if useRange {
                ToolbarItemGroup {
                    DatePicker("From", selection: $from, displayedComponents: .date).labelsHidden()
                    DatePicker("To", selection: $to, displayedComponents: .date).labelsHidden()
                }
                if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
            }
            ToolbarItem {
                Toggle(isOn: $useRange) { Label("Date Range", systemImage: "calendar") }
                    .help("Limit to a date range")
            }
        }
        .onAppear(perform: load)
        .onChange(of: useRange) { load() }
        .onChange(of: from) { load() }
        .onChange(of: to) { load() }
        .sheet(item: $editing) { p in
            MoneyEditor(model: model, project: p) { editing = nil; load() }
        }
    }

    private func project(_ ids: Set<Row.ID>) -> Project? {
        guard ids.count == 1 else { return nil }
        return rows.flatMap { $0.children ?? [] }.first { $0.id == ids.first }?.p?.project
    }

    /// Client rows (no Project) are larger and taller, so each Client reads as a group; Closed Projects are greyed.
    private func cell(_ r: Row, _ text: String, trailing: Bool = false) -> some View {
        Text(text)
            .font(r.p == nil ? .system(size: 13, weight: .semibold) : .body)
            .monospacedDigit()
            .foregroundStyle(r.p?.closed == true ? .secondary : .primary)
            .padding(.vertical, r.p == nil ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func hours(_ s: Double) -> String { String(format: "%.1f h", s / 3600) }

    /// Raw cents -> text under the Net/Gross Switch (applied to every amount shown).
    /// Amount columns follow the Net/Gross Switch, so their titles say which one they show.
    private var modeLabel: String { model.amountMode == .net ? "Net" : "Gross" }

    private func euro(_ cents: Int, perHour: Bool = false) -> String {
        let v = Money.display(cents, mode: model.amountMode, taxBps: model.taxBps)
        return String(format: "%.2f €", Double(v) / 100) + (perHour ? "/h" : "")
    }

    private func load() {
        do {
            let day: TimeInterval = 86_400
            let range = useRange ? Calendar.current.startOfDay(for: from) ..< Calendar.current.startOfDay(for: to).addingTimeInterval(day) : nil
            rows = try model.tracker.overview(range: range).map { c in
                Row(id: "c\(c.client.id!)", name: c.client.name, seconds: c.seconds, revenueCents: c.revenueCents,
                    children: c.projects.map {
                        Row(id: "p\($0.project.id!)", name: $0.project.name, seconds: $0.seconds, revenueCents: $0.revenueCents, p: $0)
                    })
            }
        } catch { model.error = "\(error)" }
    }
}

struct MoneyEditor: View {
    let model: TrayModel
    let project: Project
    let done: () -> Void
    @State private var rate = ""
    @State private var kind = 0  // 0 none, 1 hourly, 2 fixed
    @State private var price = ""
    @State private var hours = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section(project.name) {
                TextField("Rate (€/h)", text: $rate)
                Picker("Billing", selection: $kind) {
                    Text("None").tag(0); Text("Hourly").tag(1); Text("Fixed").tag(2)
                }
                if kind == 2 {
                    TextField("Agreed price (€)", text: $price)
                    TextField("Estimated hours", text: $hours)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .formSheet(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done).keyboardShortcut(.cancelAction) }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.keyboardShortcut(.defaultAction) }
        }
        .onAppear {
            guard let m = try? model.tracker.money(projectId: project.id!) else { return }
            rate = m.rateCents.map { String(format: "%g", Double($0) / 100) } ?? ""
            switch m.billing {
            case nil: kind = 0
            case .hourly: kind = 1
            case let .fixed(p, h): kind = 2; price = String(format: "%g", Double(p) / 100); hours = String(format: "%g", h)
            }
        }
    }

    /// "50", "50,5", "50.50" -> cents; nil when empty or not a number.
    static func cents(_ s: String) -> Int? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")).map { Int(($0 * 100).rounded()) }
    }

    private func save() {
        let billing: Billing?
        switch kind {
        case 1: billing = .hourly
        case 2:
            guard let p = Self.cents(price), let h = Double(hours.replacingOccurrences(of: ",", with: ".")) else { error = "Fixed needs a price and estimated hours"; return }
            billing = .fixed(priceCents: p, estimatedHours: h)
        default: billing = nil
        }
        do {
            try model.tracker.setMoney(projectId: project.id!, ProjectMoney(rateCents: Self.cents(rate), billing: billing))
            done()
        } catch { self.error = "Invalid amounts" }
    }
}
