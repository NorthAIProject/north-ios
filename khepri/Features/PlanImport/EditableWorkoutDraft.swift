import Foundation
import NorthAPI

/// A draft being reviewed, with stable identities for its rows.
///
/// The generated types compare by value, so using them as list identity would
/// give a row a new identity on every keystroke and drop the keyboard focus.
struct EditableWorkoutDraft {
    var name: String
    var days: [Day]
    var unparsed: [String]

    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    struct Day: Identifiable {
        let id = UUID()
        var label: String
        var weekday: String
        var exercises: [Item]
    }

    struct Item: Identifiable {
        let id = UUID()
        var exercise: WorkoutImportExercise
    }

    init(_ draft: WorkoutImportDraft) {
        name = draft.name
        unparsed = draft.unparsed
        days = draft.days.map { day in
            Day(label: day.label, weekday: day.weekday, exercises: day.exercises.map { Item(exercise: $0) })
        }
    }

    var draft: WorkoutImportDraft {
        WorkoutImportDraft(
            name: name,
            days: days.map { day in
                WorkoutImportDay(label: day.label, weekday: day.weekday, exercises: day.exercises.map(\.exercise))
            },
            unparsed: unparsed
        )
    }

    /// Every day has its own weekday and every exercise a name: what saving
    /// needs.
    var isReadyToSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !days.isEmpty
            && days.allSatisfy { !$0.weekday.isEmpty && !$0.exercises.isEmpty }
            && days.allSatisfy { day in
                day.exercises.allSatisfy { !$0.exercise.name.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            && repeatedWeekdays.isEmpty
    }

    /// Weekdays given to more than one day, which saving refuses.
    var repeatedWeekdays: Set<String> {
        var seen: Set<String> = []
        var repeated: Set<String> = []
        for weekday in days.map(\.weekday) where !weekday.isEmpty {
            if !seen.insert(weekday).inserted { repeated.insert(weekday) }
        }
        return repeated
    }

    /// Some exercise has no set count, so it won't appear in a live workout.
    var hasMissingSets: Bool {
        days.contains { $0.exercises.contains { $0.exercise.sets == nil } }
    }
}
