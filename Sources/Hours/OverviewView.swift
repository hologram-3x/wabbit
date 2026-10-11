import HoursCore
import SwiftUI

/// Overview per Client and Project, plus the money settings (Tax Rate, Net/Gross, Rate, Billing).
struct OverviewView: View {
    let model: TrayModel
    @State private var rows: [ClientOverview] = []
    @State private var useRange = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var to = Date.now
    @State private var taxPercent = ""
    @State private var mode = AmountMode.gross
    @State private var taxBps = 0
    @State private var editing: Project?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Amounts", selection: $mode) {
                    Text("Gross").tag(AmountMode.gross)
                    Text("Net").tag(AmountMode.net)
                }.pickerStyle(.segmented).frame(width: 180)
                TextField("Tax Rate %", text: $taxPercent).frame(width: 90).onSubmit(saveTax)
                Spacer()
                Toggle("Date range", isOn: $useRange)
                if useRange {
                    DatePicker("", selection: $from, displayedComponents: .date).labelsHidden()
                    DatePicker("", selection: $to, displayedComponents: .date).labelsHidden()
                }
            }
            List {
                ForEach(rows, id: \.client.id) { c in
                    Section("\(c.client.name)  \(hours(c.seconds))  \(euro(c.revenueCents))") {
                        ForEach(c.projects, id: \.project.id) { p in row(p) }
                    }
                }
            }
            if let e = model.error { Text(e).foregroundStyle(.red) }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
        .onAppear(perform: load)
        .onChange(of: useRange) { load() }
        .onChange(of: from) { load() }
        .onChange(of: to) { load() }
        .onChange(of: mode) { try? model.tracker.setAmountMode(mode); load() }
        .sheet(item: $editing) { p in
            MoneyEditor(model: model, project: p) { editing = nil; load() }
        }
    }

    private func row(_ p: ProjectOverview) -> some View {
        HStack {
            Text(p.project.name + (p.closed ? " (closed)" : "")).opacity(p.closed ? 0.5 : 1)
            Spacer()
            Text(hours(p.seconds))
            Text(euro(p.revenueCents))
            if let eff = p.effectiveRateCents {
                Text("eff. \(euro(eff, perHour: true)) vs \(p.rateCents.map { euro($0, perHour: true) } ?? "no Rate")")
            } else if let r = p.rateCents {
                Text(euro(r, perHour: true))
            }
            if let pct = p.percentOfEstimate { Text("\(Int(pct.rounded()))% of est.") }
            if p.overEstimate { Label("Over estimate", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if p.underRate { Label("Under Rate", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            Button("Rate & Billing…") { editing = p.project }
        }
    }

    private func hours(_ s: Double) -> String { String(format: "%.1f h", s / 3600) }

    /// Raw cents -> text under the Net/Gross Switch (applied to every amount shown).
    private func euro(_ cents: Int, perHour: Bool = false) -> String {
        let v = Money.display(cents, mode: mode, taxBps: taxBps)
        return String(format: "%.2f €", Double(v) / 100) + (perHour ? "/h" : "")
    }

    private func saveTax() {
        guard let pct = Double(taxPercent.replacingOccurrences(of: ",", with: ".")) else { return }
        do { try model.tracker.setTaxRateBps(Int((pct * 100).rounded())); model.error = nil } catch { model.error = "Tax Rate must be 0 to under 100" }
        load()
    }

    private func load() {
        do {
            mode = try model.tracker.amountMode()
            taxBps = try model.tracker.taxRateBps()
            taxPercent = String(format: "%g", Double(taxBps) / 100)
            let day: TimeInterval = 86_400
            let range = useRange ? Calendar.current.startOfDay(for: from) ..< Calendar.current.startOfDay(for: to).addingTimeInterval(day) : nil
            rows = try model.tracker.overview(range: range)
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

    var body: some View {
        Form {
            Text(project.name).font(.headline)
            TextField("Rate (€/h)", text: $rate)
            Picker("Billing", selection: $kind) {
                Text("None").tag(0); Text("Hourly").tag(1); Text("Fixed").tag(2)
            }
            if kind == 2 {
                TextField("Agreed price (€)", text: $price)
                TextField("Estimated hours", text: $hours)
            }
            HStack {
                Button("Cancel", action: done)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            if let e = model.error { Text(e).foregroundStyle(.red) }
        }
        .padding().frame(width: 320)
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

    private func cents(_ s: String) -> Int? {
        Double(s.replacingOccurrences(of: ",", with: ".")).map { Int(($0 * 100).rounded()) }
    }

    private func save() {
        let billing: Billing?
        switch kind {
        case 1: billing = .hourly
        case 2:
            guard let p = cents(price), let h = Double(hours.replacingOccurrences(of: ",", with: ".")) else { model.error = "Fixed needs a price and estimated hours"; return }
            billing = .fixed(priceCents: p, estimatedHours: h)
        default: billing = nil
        }
        do {
            try model.tracker.setMoney(projectId: project.id!, ProjectMoney(rateCents: cents(rate), billing: billing))
            model.error = nil
            done()
        } catch { model.error = "Invalid amounts" }
    }
}
