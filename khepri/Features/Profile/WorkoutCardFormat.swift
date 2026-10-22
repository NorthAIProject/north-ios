import Foundation
import NorthAPI

/// What a workout card says, as plain strings. Pure, so the rules (leave out
/// a zero, never "0 sets", the reader's decimal mark) are testable. The card
/// carries no calories, heart rate or body numbers, so none appear here.
enum WorkoutCardFormat {
    /// How many movements a card names.
    static let topExercises = 2

    static func top(_ card: WorkoutCard) -> [WorkoutExercise] {
        Array(card.exercises.prefix(topExercises))
    }

    /// Time, sets, volume, then distance. A part that is zero is left out.
    static func stats(_ card: WorkoutCard, locale: Locale = .autoupdatingCurrent) -> [String] {
        var parts: [String] = []
        let minutes = Int((Double(card.durationSeconds) / 60).rounded())
        if minutes > 0 { parts.append(String(localized: "\(minutes) min")) }
        if let sets = setsText(card.sets) { parts.append(sets) }
        if card.volumeKg > 0 { parts.append(volume(card.volumeKg, locale: locale)) }
        if let meters = card.distanceM, meters > 0 {
            // One decimal at most, trimmed: "5 km", "5.2 km".
            let km = (meters / 100).rounded() / 10
            let shown = km.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
            parts.append(String(localized: "\(shown) km"))
        }
        return parts
    }

    /// "9 sets", "1 set", and nil for none: a session without sets says nothing.
    static func setsText(_ sets: Int) -> String? {
        switch sets {
        case ..<1: nil
        case 1: String(localized: "1 set")
        default: String(localized: "\(sets) sets")
        }
    }

    /// Whole kilograms, grouped the reader's way.
    static func volume(_ kg: Double, locale: Locale = .autoupdatingCurrent) -> String {
        String(localized: "\(Int(kg.rounded()).formatted(.number.locale(locale))) kg")
    }

    /// The server writes the heaviest set with a point ("22.5 kg × 8"); the
    /// reader's decimal mark replaces it.
    static func best(_ text: String, locale: Locale = .autoupdatingCurrent) -> String {
        let mark = locale.decimalSeparator ?? "."
        guard mark != "." else { return text }
        return text.replacingOccurrences(of: #"(\d)\.(\d)"#, with: "$1\(mark)$2", options: .regularExpression)
    }

    /// The line under an exercise on the detail screen.
    static func detail(_ exercise: WorkoutExercise, locale: Locale = .autoupdatingCurrent) -> String {
        var parts: [String] = []
        if let sets = setsText(exercise.sets) { parts.append(sets) }
        if exercise.volumeKg > 0 { parts.append(volume(exercise.volumeKg, locale: locale)) }
        if let best = exercise.best, !best.isEmpty { parts.append(Self.best(best, locale: locale)) }
        return parts.joined(separator: " · ")
    }

    /// The exercises where this workout set a record, in card order.
    static func recordNames(_ card: WorkoutCard) -> [String] {
        card.exercises.filter(\.pr).map(\.name)
    }

    /// Records the card counts but does not name: the API carries only the top
    /// two exercises, so a record on the third or later shows as "+N PR".
    static func unnamedRecords(_ card: WorkoutCard) -> Int {
        max(0, card.prs - recordNames(card).count)
    }
}
