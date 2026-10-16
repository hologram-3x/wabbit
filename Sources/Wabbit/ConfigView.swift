import WabbitCore
import SwiftUI

/// The freelancer's own settings. Text fields save on Return or when focus leaves them.
struct ConfigView: View {
    let model: TrayModel
    @State private var rate = ""
    @State private var tax = ""
    @FocusState private var focus: Field?
    private enum Field { case rate, tax }

    var body: some View {
        Form {
            Section("Money") {
                TextField("Default Rate (€/h)", text: $rate, prompt: Text("None"))
                    .focused($focus, equals: .rate).onSubmit(saveRate)
                Text("New Projects and Projects without a Rate get this one.").foregroundStyle(.secondary).font(.caption)
                TextField("Tax Rate %", text: $tax)
                    .focused($focus, equals: .tax).onSubmit(saveTax)
                Picker("Amounts", selection: Binding(get: { model.amountMode }, set: { model.setAmountMode($0) })) {
                    Text("Gross").tag(AmountMode.gross)
                    Text("Net").tag(AmountMode.net)
                }.pickerStyle(.segmented)
                Text("Your hourly Rate for new Projects, and how tax is applied. Gross: amounts are what the Client pays; Net: what you keep after tax.")
                    .foregroundStyle(.secondary).font(.caption)
            }
            Section("Tracking") {
                Picker("Idle Threshold", selection: Binding(
                    get: { model.idleThresholdMinutes }, set: { model.setIdleThresholdMinutes($0) }
                )) {
                    ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { m in
                        Text(m < 60 ? "\(m) min" : "1 h").tag(m)
                    }
                }
                Stepper("Watched App prompt after \(model.watchedDelaySeconds) s in front",
                        value: Binding(get: { model.watchedDelaySeconds }, set: { model.setWatchedDelay($0) }),
                        in: 5...600, step: 5)
            }
            Section("Export rounding") {
                Picker("Step", selection: Binding(
                    get: { model.roundingStepMinutes }, set: { model.setRoundingStepMinutes($0) }
                )) {
                    Text("30 min").tag(30)
                    Text("1 h").tag(60)
                }
                Picker("Threshold", selection: Binding(
                    get: { model.roundingThresholdMinutes }, set: { model.setRoundingThresholdMinutes($0) }
                )) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
                Text("Rounded CSV exports round each Session to the Step: down when at most the Threshold past it, up otherwise (e.g. 1h10 → 1h, 1h20 → 2h). Tracked time is always stored precisely.")
                    .foregroundStyle(.secondary).font(.caption)
            }
            Section("App") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Button("Check for Updates…") { model.updater.checkForUpdates(nil) }
                    .disabled(!TrayModel.updatesEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: focus) { old, _ in
            if old == .rate { saveRate() }
            if old == .tax { saveTax() }
        }
    }

    private func load() {
        rate = model.defaultRateCents.map { String(format: "%g", Double($0) / 100) } ?? ""
        tax = String(format: "%g", Double(model.taxBps) / 100)
    }

    private func saveRate() {
        let trimmed = rate.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty || MoneyEditor.cents(trimmed).map({ $0 >= 0 }) == true else {
            model.error = "Default Rate must be an amount like 50 or 50,50"; return
        }
        model.setDefaultRateCents(MoneyEditor.cents(trimmed))
        load()
    }

    private func saveTax() {
        guard let bps = MoneyEditor.cents(tax), (0..<10_000).contains(bps) else {
            model.error = "Tax Rate must be 0 to under 100"; return
        }
        model.setTaxRateBps(bps)
        load()
    }
}
