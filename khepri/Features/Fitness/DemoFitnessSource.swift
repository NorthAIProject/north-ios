#if DEBUG
import Foundation
import HealthKit

/// Two weeks of plausible Apple Health data for the App Store screenshots
/// (`-uitest-demo-health`), because the simulator's Health store is empty and
/// the server seed cannot reach it. Debug builds only.
struct DemoFitnessSource: FitnessDataSource {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitest-demo-health") }

    var isAvailable: Bool { true }

    func snapshot(now: Date, calendar: Calendar) async throws -> FitnessSnapshot {
        let today = calendar.startOfDay(for: now)
        let stepsByAge: [Double] = [6_840, 9_120, 11_460, 7_310, 12_880, 8_050, 10_240,
                                    7_920, 11_030, 6_480, 9_870, 13_150, 8_620, 9_410]
        let days = stepsByAge.indices.reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let steps = zip(days, stepsByAge.reversed()).map { DailyValue(day: $0, value: $1) }
        let exercise = steps.map { DailyValue(day: $0.day, value: ($0.value / 220).rounded()) }
        let distance = steps.map { DailyValue(day: $0.day, value: ($0.value * 0.00074 * 10).rounded() / 10) }
        let sessions: [(age: Int, type: HKWorkoutActivityType, minutes: Int, meters: Double?)] =
            [(1, .running, 38, 6_200), (3, .traditionalStrengthTraining, 45, nil), (5, .running, 52, 8_100), (8, .running, 38, 6_100)]
        let workouts: [FitnessWorkout] = sessions.compactMap { age, type, minutes, meters in
            guard let day = calendar.date(byAdding: .day, value: -age, to: today),
                  let start = calendar.date(bySettingHour: 7, minute: 15, second: 0, of: day) else { return nil }
            return FitnessWorkout(id: UUID(), type: type, start: start, duration: Double(minutes) * 60, meters: meters)
        }
        return FitnessSnapshot(steps: steps, exerciseMinutes: exercise, distanceKm: distance, workouts: workouts)
    }
}
#endif
