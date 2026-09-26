import NorthAPI
import NorthKit
import SwiftUI

/// The "+" on My Day: every tracker one or two taps away. Each tap writes and
/// reloads the day; the sheet stays open so several things can go in at once.
struct QuickAddSheet: View {
    let store: DayStore
    @Environment(\.dismiss) private var dismiss
    @State private var supplement = DayMath.supplementPresets[0].key
    @State private var supplementCount = 1
    @State private var screenHours = 0
    @State private var screenMinutes = 0
    @State private var trackerName = ""
    @State private var trackerDate = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("Water") {
                    HStack {
                        ForEach([250, 330, 500], id: \.self) { ml in
                            Button("\(ml) ml") { run { try await $0.logWater(ml) } }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("Caffeine") {
                    ForEach(DayMath.caffeinePresets, id: \.key) { preset in
                        Button {
                            let key = preset.key
                            run { try await $0.logCaffeine(preset: key) }
                        } label: {
                            LabeledContent(String(localized: preset.name), value: "\(preset.mg) mg")
                        }
                    }
                }
                Section("Supplements") {
                    Picker("Supplement", selection: $supplement) {
                        ForEach(DayMath.supplementPresets, id: \.key) { Text($0.name).tag($0.key) }
                    }
                    Stepper("How many: \(supplementCount)", value: $supplementCount, in: 1...20)
                    Button("Log supplement") {
                        let preset = supplement, count = supplementCount
                        run { try await $0.logSupplement(preset: preset, count: count) }
                    }
                }
                Section {
                    ScreenTimeReportView()
                    Stepper("Hours: \(screenHours)", value: $screenHours, in: 0...24)
                    Stepper("Minutes: \(screenMinutes)", value: $screenMinutes, in: 0...55, step: 5)
                    Button("Save screen time") {
                        let total = screenHours * 60 + screenMinutes
                        run { try await $0.setScreenTime(minutes: total) }
                    }
                } header: {
                    Text("Screen time today")
                } footer: {
                    Text("Apple keeps screen time on the phone. Enter it here, or run a Shortcut that sends it.")
                }
                Section("Months since") {
                    ForEach(store.day?.milestones ?? [], id: \.id) { tracker in
                        LabeledContent(tracker.name) {
                            Button("Done today") {
                                let id = tracker.id
                                run { try await $0.trackerDone(id: id) }
                            }
                        }
                    }
                    TextField("Dentist, haircut…", text: $trackerName)
                    DatePicker("Last done", selection: $trackerDate, in: ...Date.now, displayedComponents: .date)
                    Button("Add tracker") {
                        let name = trackerName, date = trackerDate
                        trackerName = ""
                        run { try await $0.createTracker(name: name, lastDone: date) }
                    }
                    .disabled(trackerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = store.actionError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add to your day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func run(_ action: @escaping @Sendable (DayActing) async throws -> Void) {
        Task { await store.perform(action) }
    }
}

/// Soreness, target weight and blood pressure.
struct BodySheet: View {
    let day: DayResponse
    let store: DayStore
    @Environment(\.dismiss) private var dismiss
    @State private var region = DayMath.regions[0].key
    @State private var target: Double?
    @State private var systolic = 120
    @State private var diastolic = 80

    var body: some View {
        NavigationStack {
            Form {
                Section("Where is it sore?") {
                    Picker("Region", selection: $region) {
                        ForEach(DayMath.regions, id: \.key) { Text(String(localized: $0.name)).tag($0.key) }
                    }
                    HStack {
                        ForEach(1...3, id: \.self) { severity in
                            Button(DayMath.severityName(severity)) {
                                let r = region
                                run { try await $0.setSoreness(region: r, severity: severity) }
                            }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(day.body.soreness, id: \.region) { sore in
                        LabeledContent(DayMath.regionName(sore.region), value: DayMath.severityName(sore.severity))
                            .swipeActions {
                                Button("Clear", role: .destructive) {
                                    let r = sore.region
                                    run { try await $0.clearSoreness(region: r) }
                                }
                            }
                    }
                }
                Section("Target weight") {
                    TextField("kg", value: $target, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                    Button("Save target") {
                        let kg = target
                        run { try await $0.setTargetWeight(kg) }
                    }
                }
                Section("Blood pressure") {
                    Stepper("Systolic: \(systolic)", value: $systolic, in: 60...260)
                    Stepper("Diastolic: \(diastolic)", value: $diastolic, in: 30...160)
                    Button("Save reading") {
                        let sys = systolic, dia = diastolic
                        run { try await $0.recordBloodPressure(systolic: sys, diastolic: dia) }
                    }
                }
                if let error = store.actionError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { target = day.body.targetWeightKg }
        }
    }

    private func run(_ action: @escaping @Sendable (DayActing) async throws -> Void) {
        Task { await store.perform(action) }
    }
}
