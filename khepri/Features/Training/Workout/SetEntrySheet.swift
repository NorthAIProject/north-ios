import NorthAPI
import NorthKit
import SwiftUI

/// Asked before a set counts as done: what was on the bar and how many reps.
/// Prefilled from this workout's previous set or from last time, so most sets
/// are one tap.
struct SetEntrySheet: View {
    let exerciseName: String
    let setNumber: Int
    let lastTime: [LiftSet]
    let imperial: Bool
    let onLog: (_ weightKg: Double, _ reps: Int) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var bodyweight: Bool
    @Environment(\.dismiss) private var dismiss

    init(exerciseName: String, setNumber: Int, suggestedWeightKg: Double?, suggestedReps: Int,
         lastTime: [LiftSet], imperial: Bool, onLog: @escaping (_ weightKg: Double, _ reps: Int) -> Void) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.lastTime = lastTime
        self.imperial = imperial
        self.onLog = onLog
        _weight = State(initialValue: LiftMath.display(suggestedWeightKg ?? 0, imperial: imperial))
        _reps = State(initialValue: suggestedReps)
        _bodyweight = State(initialValue: suggestedWeightKg == 0)
    }

    private var unit: String { imperial ? "lb" : "kg" }
    private var step: Double { imperial ? 5 : 2.5 }

    var body: some View {
        NavigationStack {
            Form {
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
                            set.weightKg == 0 ? "BW × \(set.reps)"
                                : "\(LiftMath.display(set.weightKg, imperial: imperial).formatted()) × \(set.reps)"
                        }.joined(separator: ", "))
                    }
                }

                Section("Reps") {
                    Stepper(value: $reps, in: 1...100) {
                        Text("\(reps) reps").font(.headline.monospacedDigit())
                    }
                }
            }
            .navigationTitle("\(exerciseName) · Set \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log Set") {
                        let kg = bodyweight ? 0 : LiftMath.kilograms(max(0, weight), imperial: imperial)
                        onLog((kg * 10).rounded() / 10, reps)
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
