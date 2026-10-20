import Foundation
import NorthAPI

/// The numbers half of a new progress check, as typed. Every field is
/// optional; a blank one is not measured.
///
/// Fields hold text rather than numbers so a half-typed "82," survives, and
/// either decimal mark reads, as on the web.
struct ProgressCheckDraft: Equatable {
    enum Field: String, CaseIterable, Identifiable {
        case weight, waist, hips, chest, thigh, arm
        var id: Self { self }

        var unit: String { self == .weight ? "kg" : "cm" }

        var title: String {
            switch self {
            case .weight: String(localized: "Weight")
            case .waist: String(localized: "Waist")
            case .hips: String(localized: "Hips")
            case .chest: String(localized: "Chest")
            case .thigh: String(localized: "Thigh")
            case .arm: String(localized: "Arm")
            }
        }

        /// The ones a photo estimate can fill.
        static let estimated: [Field] = [.waist, .hips, .chest]
    }

    /// What an estimate did to the draft, shown under the numbers.
    struct EstimateOutcome: Equatable {
        var confidence: String
        var notes: String
        /// Empty fields it filled.
        var filled: Int
        /// Fields it estimated but left alone, because a number was typed.
        var kept: Int
    }

    var measuredOn: Date = .now
    var values: [Field: String] = [:]
    /// "assisted" once an estimate filled a field; the save carries it with
    /// the estimate's confidence and note.
    var source = "manual"
    var assistConfidence: String?
    var assistNotes: String?

    /// A field's number, or nil when it is blank or not a number.
    func number(_ field: Field) -> Double? {
        Self.number(values[field] ?? "")
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    /// Typed, but not a number: the save waits until they are fixed.
    var invalidFields: [Field] {
        Field.allCases.filter { field in
            let text = (values[field] ?? "").trimmingCharacters(in: .whitespaces)
            return !text.isEmpty && Self.number(text) == nil
        }
    }

    var hasMeasurement: Bool {
        Field.allCases.contains { number($0) != nil }
    }

    func input(cadence: String? = nil) -> ProgressCheckInput {
        ProgressCheckInput(
            measuredOn: CalendarDay.string(from: measuredOn),
            cadence: cadence,
            weightKg: number(.weight),
            waistCm: number(.waist),
            hipsCm: number(.hips),
            chestCm: number(.chest),
            thighCm: number(.thigh),
            armCm: number(.arm),
            source: source,
            assistConfidence: source == "assisted" ? assistConfidence : nil,
            assistNotes: source == "assisted" ? assistNotes : nil
        )
    }

    /// Fills the empty fields from an estimate and keeps what was typed: the
    /// person is about to save these numbers as theirs.
    mutating func apply(_ estimate: Components.Schemas.ProgressEstimate) -> EstimateOutcome {
        let guesses: [Field: Double?] = [.waist: estimate.waistCm, .hips: estimate.hipsCm, .chest: estimate.chestCm]
        var outcome = EstimateOutcome(confidence: estimate.confidence, notes: estimate.notes, filled: 0, kept: 0)
        for field in Field.estimated {
            guard let guess = guesses[field] ?? nil, guess > 0 else { continue }
            if number(field) == nil {
                values[field] = guess.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
                outcome.filled += 1
            } else {
                outcome.kept += 1
            }
        }
        if outcome.filled > 0 {
            source = "assisted"
            assistConfidence = estimate.confidence
            assistNotes = estimate.notes
        }
        return outcome
    }
}

/// One measurement of a saved check as the history shows it.
struct ProgressChip: Equatable, Identifiable {
    var field: ProgressCheckDraft.Field
    var value: Double
    /// The change since the check before, when that had it too; nil when
    /// there is nothing to compare or nothing changed.
    var delta: Double?
    /// A weight copied from the last known one, not read off a scale.
    var carried: Bool
    var id: ProgressCheckDraft.Field { field }
}

extension ProgressCheck {
    func value(_ field: ProgressCheckDraft.Field) -> Double? {
        switch field {
        case .weight: weightKg
        case .waist: waistCm
        case .hips: hipsCm
        case .chest: chestCm
        case .thigh: thighCm
        case .arm: armCm
        }
    }

    /// Each number against the check before it. A carried weight is not a
    /// reading, so it neither shows a change nor is one to compare against.
    func chips(since older: ProgressCheck?) -> [ProgressChip] {
        ProgressCheckDraft.Field.allCases.compactMap { field in
            guard let value = value(field) else { return nil }
            let isWeight = field == .weight
            if isWeight, weightCarried { return ProgressChip(field: field, value: value, delta: nil, carried: true) }
            var delta: Double?
            if let older, let was = older.value(field), !(isWeight && older.weightCarried) {
                let change = ((value - was) * 10).rounded() / 10
                delta = change == 0 ? nil : change
            }
            return ProgressChip(field: field, value: value, delta: delta, carried: false)
        }
    }

    func photo(_ pose: ProgressPose) -> Components.Schemas.ProgressPhoto? {
        photos.first { $0.pose == pose.rawValue }
    }

    var isAssisted: Bool { source == "assisted" }
}

extension ProgressChecks {
    /// For each pose, the newest photo any check has: a check saved with
    /// numbers only still leaves the last photos to compare against.
    var lastPhotos: [ProgressPose: Components.Schemas.ProgressPhoto] {
        var out: [ProgressPose: Components.Schemas.ProgressPhoto] = [:]
        for check in checks {
            for pose in ProgressPose.allCases where out[pose] == nil {
                out[pose] = check.photo(pose)
            }
        }
        return out
    }
}
