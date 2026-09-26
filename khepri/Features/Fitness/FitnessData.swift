import Foundation
import HealthKit

/// A workout as the Fitness screen lists it.
struct FitnessWorkout: Equatable, Identifiable {
    var id: UUID
    var type: HKWorkoutActivityType
    var start: Date
    var duration: TimeInterval
    var meters: Double?

    var name: String { FitnessWorkout.name(for: type) }
    var systemImage: String { FitnessWorkout.systemImage(for: type) }

    var km: Double? { meters.map { $0 / 1000 } }

    /// Minutes per km, for the kinds of workout people think of in pace.
    var paceSecondsPerKm: Double? {
        guard [.walking, .running, .hiking].contains(type), let km, km >= 0.1 else { return nil }
        return duration / km
    }

    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Walk"
        case .running: "Run"
        case .cycling: "Ride"
        case .hiking: "Hike"
        case .swimming: "Swim"
        case .rowing: "Row"
        case .elliptical: "Elliptical"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .coreTraining: "Core"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .flexibility, .cooldown: "Stretching"
        case .dance, .socialDance, .cardioDance: "Dance"
        case .stairClimbing, .stairs: "Stairs"
        case .mixedCardio: "Cardio"
        default: "Workout"
        }
    }

    static func systemImage(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .hiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "dumbbell.fill"
        case .coreTraining: "figure.core.training"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .flexibility, .cooldown: "figure.flexibility"
        case .dance, .socialDance, .cardioDance: "figure.dance"
        case .stairClimbing, .stairs: "figure.stairs"
        default: "figure.mixed.cardio"
        }
    }
}

/// What the Fitness screen reads from Apple Health, all on the phone.
struct FitnessSnapshot: Equatable {
    /// Daily step totals, oldest first, for the last two weeks at least.
    var steps: [DailyValue] = []
    /// Daily Apple Exercise minutes over the same window.
    var exerciseMinutes: [DailyValue] = []
    /// Daily walking and running distance in km over the same window.
    var distanceKm: [DailyValue] = []
    /// Newest first.
    var workouts: [FitnessWorkout] = []
    /// Daily VO2 max averages, oldest first, over the last few months.
    var vo2Max: [DailyValue] = []

    var isEmpty: Bool { steps.isEmpty && workouts.isEmpty && vo2Max.isEmpty }
}

/// Reads a snapshot. A protocol so the store can be tested without HealthKit.
protocol FitnessDataSource: Sendable {
    var isAvailable: Bool { get }
    func snapshot(now: Date, calendar: Calendar) async throws -> FitnessSnapshot
}

struct HealthKitFitnessSource: FitnessDataSource {
    static let dailyWindowDays = 14
    static let workoutWindowDays = 30
    static let vo2WindowDays = 90

    var store: HKHealthStore = HealthStore.shared

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func snapshot(now: Date, calendar: Calendar) async throws -> FitnessSnapshot {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let twoWeeks = calendar.date(byAdding: .day, value: -(Self.dailyWindowDays - 1), to: today) ?? today
        let from = min(weekStart, twoWeeks)
        let workoutsFrom = calendar.date(byAdding: .day, value: -Self.workoutWindowDays, to: today) ?? today
        let vo2From = calendar.date(byAdding: .day, value: -Self.vo2WindowDays, to: today) ?? today

        async let steps = store.dailyValues(.stepCount, .count(), .cumulativeSum, from: from, to: now, calendar: calendar)
        async let exercise = store.dailyValues(.appleExerciseTime, .minute(), .cumulativeSum, from: from, to: now, calendar: calendar)
        async let distance = store.dailyValues(.distanceWalkingRunning, .meterUnit(with: .kilo), .cumulativeSum, from: from, to: now, calendar: calendar)
        async let vo2 = store.dailyValues(.vo2Max, .vo2Max, .discreteAverage, from: vo2From, to: now, calendar: calendar)
        async let workouts = workouts(from: workoutsFrom, to: now)

        return try await FitnessSnapshot(steps: steps, exerciseMinutes: exercise, distanceKm: distance,
                                         workouts: workouts, vo2Max: vo2)
    }

    private func workouts(from start: Date, to end: Date) async throws -> [FitnessWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try await descriptor.result(for: store).map { w in
            FitnessWorkout(id: w.uuid, type: w.workoutActivityType, start: w.startDate,
                           duration: w.duration, meters: distance(of: w))
        }
    }

    private func distance(of workout: HKWorkout) -> Double? {
        let kinds: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for kind in kinds {
            if let meters = workout.statistics(for: HKQuantityType(kind))?.sumQuantity()?.doubleValue(for: .meter()), meters > 0 {
                return meters
            }
        }
        return nil
    }
}

// MARK: - The week

/// This calendar week at a glance: totals, and one bar per day.
struct FitnessWeek: Equatable {
    struct Day: Equatable, Identifiable {
        var date: Date
        /// "Su", "Mo", … in the person's locale.
        var label: String
        var steps: Double
        /// A workout started that day.
        var active: Bool
        var isToday: Bool
        var isFuture: Bool

        var id: Date { date }
    }

    var days: [Day]
    var steps: Double
    var exerciseMinutes: Double
    var distanceKm: Double
    /// Workouts started this week.
    var workouts: Int

    /// Steps per day over the days that have any, so a week that has just
    /// begun is not dragged down by days still to come.
    var stepsPerDay: Double {
        let counted = days.filter { $0.steps > 0 }.count
        return counted == 0 ? 0 : steps / Double(counted)
    }

    init(snapshot: FitnessSnapshot, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? today
        let inWeek = { (date: Date) in date >= start && date < end }

        let symbols = calendar.shortStandaloneWeekdaySymbols.map { String($0.prefix(2)) }
        let workoutDays = Set(snapshot.workouts.filter { inWeek($0.start) }.map { calendar.startOfDay(for: $0.start) })

        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            return Day(
                date: date,
                label: symbols[weekday - 1],
                steps: snapshot.steps.first { calendar.isDate($0.day, inSameDayAs: date) }?.value ?? 0,
                active: workoutDays.contains(date),
                isToday: date == today,
                isFuture: date > today
            )
        }
        steps = snapshot.steps.filter { inWeek($0.day) }.reduce(0) { $0 + $1.value }
        exerciseMinutes = snapshot.exerciseMinutes.filter { inWeek($0.day) }.reduce(0) { $0 + $1.value }
        distanceKm = snapshot.distanceKm.filter { inWeek($0.day) }.reduce(0) { $0 + $1.value }
        workouts = snapshot.workouts.filter { inWeek($0.start) }.count
    }
}

// MARK: - Steps by day

/// One day's steps and how they compare with the day before.
struct StepDay: Equatable, Identifiable {
    var day: Date
    var steps: Double
    /// Nil for the first day there is nothing before.
    var delta: Double?

    var id: Date { day }

    /// Newest first, each against the day before it in the data.
    static func recent(_ steps: [DailyValue], limit: Int = 5) -> [StepDay] {
        let sorted = steps.sorted { $0.day < $1.day }
        let days = sorted.enumerated().map { index, value in
            StepDay(day: value.day, steps: value.value, delta: index > 0 ? value.value - sorted[index - 1].value : nil)
        }
        return Array(days.suffix(limit).reversed())
    }
}

// MARK: - Formatting

enum FitnessFormat {
    /// "325", "6.5k", "10k", "30.9k".
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude < 1000 {
            return value.rounded().formatted(.number.precision(.fractionLength(0)))
        }
        let thousands = (value / 100).rounded() / 10
        return thousands.formatted(.number.precision(.fractionLength(0...1))) + "k"
    }

    /// "+2.8k", "-1.6k", "+325", "0".
    static func signed(_ value: Double) -> String {
        let rounded = value.rounded()
        if rounded == 0 { return "0" }
        return (rounded > 0 ? "+" : "-") + compact(abs(rounded))
    }

    /// "51:51/km".
    static func pace(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    /// "1h 51m", "50m".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// "2.2 km".
    static func km(_ km: Double) -> String {
        km.formatted(.number.precision(.fractionLength(1))) + " km"
    }
}

// MARK: - VO2 max

/// Where a VO2 max sits for a person's age and sex, from the widely used
/// Cooper Institute bands, simplified to four steps.
enum VO2Rating: String, Equatable {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    static func rating(for value: Double, age: Int?, sex: String?) -> VO2Rating {
        let (fair, good, excellent) = thresholds(age: age, sex: sex)
        switch value {
        case ..<fair: return .poor
        case ..<good: return .fair
        case ..<excellent: return .good
        default: return .excellent
        }
    }

    /// The lower bounds of Fair, Good and Excellent.
    static func thresholds(age: Int?, sex: String?) -> (Double, Double, Double) {
        let band: Int = switch age ?? 35 {
        case ..<30: 0
        case ..<40: 1
        case ..<50: 2
        case ..<60: 3
        default: 4
        }
        let male: [(Double, Double, Double)] = [(38, 42, 46), (36, 40, 44), (34, 38, 42), (31, 35, 39), (28, 32, 36)]
        let female: [(Double, Double, Double)] = [(32, 36, 40), (30, 34, 38), (28, 32, 36), (25, 29, 33), (22, 26, 30)]
        switch sex?.lowercased() {
        case "male": return male[band]
        case "female": return female[band]
        default:
            let m = male[band], f = female[band]
            return ((m.0 + f.0) / 2, (m.1 + f.1) / 2, (m.2 + f.2) / 2)
        }
    }
}
