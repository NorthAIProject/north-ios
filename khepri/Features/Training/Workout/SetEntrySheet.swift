import NorthAPI
import NorthKit
import SwiftUI

/// What the set sheet hands back: the set as it was done.
struct SetEntry: Equatable {
    var weightKg: Double
    var reps: Int
    var kind: SetKind
    /// Reps in reserve; nil when skipped, and then nothing is sent.
    var rir: Int?
}

/// Asked before a set counts as done: what was on the bar, how many reps,
/// and optionally what kind of set it was and how close to failure.
/// Prefilled from this workout's previous set or from last time, so most sets
/// are one tap.
struct SetEntrySheet: View {
    let exerciseName: String
    let setNumber: Int
    let lastTime: [LiftSet]
    let imperial: Bool
    let onLog: (SetEntry) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var bodyweight: Bool
    @State private var kind: SetKind
    @State private var rir: Int?
    @Environment(\.dismiss) private var dismiss

    init(exerciseName: String, setNumber: Int, suggestedWeightKg: Double?, suggestedReps: Int,
         suggestedKind: SetKind = .work, lastTime: [LiftSet], imperial: Bool, onLog: @escaping (SetEntry) -> Void) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.lastTime = lastTime
        self.imperial = imperial
        self.onLog = onLog
        _weight = State(initialValue: LiftMath.display(suggestedWeightKg ?? 0, imperial: imperial))
        _reps = State(initialValue: suggestedReps)
        _bodyweight = State(initialValue: suggestedWeightKg == 0)
        _kind = State(initialValue: suggestedKind)
    }

    private var unit: String { imperial ? "lb" : "kg" }
    private var step: Double { imperial ? 5 : 2.5 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Set kind", selection: $kind) {
                        ForEach(SetKind.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("set-kind")
                } footer: {
                    if kind == .warmup {
                        Text("Left out of volume and records. Set \(setNumber) is still to come.")
                    }
                }

                Section {
                    if !bodyweight {
                        HStack(spacing: 16) {
                            stepButton("minus", -step)
                            TextField("Weight", value: $weight, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.north(size: 44, relativeTo: .largeTitle).weight(.semibold).monospacedDigit())
                                .accessibilityLabel("Weight in \(unit == "kg" ? "kilograms" : "pounds")")
                            stepButton("plus", step)
                        }
                        .overlay(alignment: .trailing) {
                            Text(unit).font(.subheadline).foregroundStyle(.secondary).padding(.trailing, 56)
                                .accessibilityHidden(true)
                        }
                    }
                    Toggle("Bodyweight", isOn: $bodyweight)
                } header: {
                    Text("Weight")
                } footer: {
                    if !lastTime.isEmpty {
                        Text("Last time: " + lastTime.map { set in
                            let done = set.weightKg == 0 ? "BW × \(set.reps)"
                                : "\(LiftMath.display(set.weightKg, imperial: imperial).formatted()) × \(set.reps)"
                            return set.setKind == .warmup ? "warm-up \(done)" : done
                        }.joined(separator: ", "))
                    }
                }

                Section("Reps") {
                    Stepper(value: $reps, in: 1...100) {
                        Text("\(reps) reps").font(.headline.monospacedDigit())
                    }
                }

                Section {
                    Picker("Reps in reserve", selection: $rir) {
                        Text("Skip").tag(Int?.none)
                        ForEach(RepsInReserve.choices, id: \.self) { value in
                            Text(RepsInReserve.label(value)).tag(Int?.some(value))
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("set-rir")
                } header: {
                    Text("Reps in reserve")
                } footer: {
                    Text("How many more you could have done. 0 is to failure.")
                }
            }
            .navigationTitle(kind == .warmup ? "\(exerciseName) · Warm-up" : "\(exerciseName) · Set \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log Set") {
                        let kg = bodyweight ? 0 : LiftMath.kilograms(max(0, weight), imperial: imperial)
                        onLog(SetEntry(weightKg: (kg * 10).rounded() / 10, reps: reps, kind: kind, rir: rir))
                        dismiss()
                    }
                    .disabled(!bodyweight && weight <= 0)
                    .accessibilityIdentifier("log-set")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepButton(_ symbol: String, _ delta: Double) -> some View {
        Button {
            weight = max(0, weight + delta)
        } label: {
            Image(systemName: "\(symbol).circle.fill").font(.title)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(delta > 0 ? "Add \(step.formatted()) \(unit)" : "Take off \(step.formatted()) \(unit)")
    }
}
