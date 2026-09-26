import Foundation
import HealthKit
import NorthAPI
import Testing
@testable import khepri

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = Locale(identifier: "en_US")
    c.firstWeekday = 1
    return c
}()

/// September 2026: the 20th is a Sunday, the 25th a Friday.
private func day(_ d: Int, _ hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hour))!
}

private func workout(_ type: HKWorkoutActivityType, on d: Int, minutes: Double = 45, meters: Double? = nil) -> FitnessWorkout {
    FitnessWorkout(id: UUID(), type: type, start: day(d, 17), duration: minutes * 60, meters: meters)
}

@MainActor
struct FitnessFormatTests {
    @Test func compactNumbersReadLikeTheDesign() {
        #expect(FitnessFormat.compact(325) == "325")
        #expect(FitnessFormat.compact(6_512) == "6.5k")
        #expect(FitnessFormat.compact(10_020) == "10k")
        #expect(FitnessFormat.compact(30_940) == "30.9k")
    }

    @Test func deltasCarryTheirSign() {
        #expect(FitnessFormat.signed(2_812) == "+2.8k")
        #expect(FitnessFormat.signed(-1_630) == "-1.6k")
        #expect(FitnessFormat.signed(325) == "+325")
        #expect(FitnessFormat.signed(0.2) == "0")
    }

    @Test func paceIsMinutesAndSecondsPerKm() {
        #expect(FitnessFormat.pace(3_111) == "51:51/km")
        #expect(FitnessFormat.pace(305) == "5:05/km")
    }

    @Test func onlyWalksRunsAndHikesHaveAPace() {
        #expect(workout(.walking, on: 25, minutes: 60, meters: 5_000).paceSecondsPerKm == 720)
        #expect(workout(.cycling, on: 25, minutes: 60, meters: 20_000).paceSecondsPerKm == nil)
        #expect(workout(.walking, on: 25).paceSecondsPerKm == nil, "no distance, no pace")
    }
}

@MainActor
struct StepDayTests {
    @Test func newestFirstWithTheChangeFromTheDayBefore() {
        let steps = [DailyValue(day: day(20), value: 10_500), DailyValue(day: day(21), value: 4_900),
                     DailyValue(day: day(22), value: 5_300)]
        let recent = StepDay.recent(steps)

        #expect(recent.map(\.day) == [day(22), day(21), day(20)])
        #expect(recent[0].delta == 400)
        #expect(recent[1].delta == -5_600)
        #expect(recent[2].delta == nil, "nothing before the first day")
    }

    @Test func keepsOnlyTheLatestDays() {
        let steps = (1...10).map { DailyValue(day: day($0), value: Double($0)) }
        let recent = StepDay.recent(steps, limit: 5)
        #expect(recent.count == 5)
        #expect(recent.last?.delta == 1, "the oldest shown still compares with the day before it")
    }
}

@MainActor
struct FitnessWeekTests {
    @Test func bucketsTheCalendarWeekAndMarksToday() {
        let snapshot = FitnessSnapshot(
            steps: [DailyValue(day: day(19), value: 9_999), DailyValue(day: day(20), value: 10_000),
                    DailyValue(day: day(21), value: 5_000), DailyValue(day: day(25), value: 3_000)],
            exerciseMinutes: [DailyValue(day: day(20), value: 90), DailyValue(day: day(25), value: 30)],
            distanceKm: [DailyValue(day: day(20), value: 6.5)],
            workouts: [workout(.walking, on: 25), workout(.traditionalStrengthTraining, on: 21), workout(.running, on: 18)]
        )
        let week = FitnessWeek(snapshot: snapshot, now: day(25, 19), calendar: calendar)

        #expect(week.days.map(\.label) == ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"])
        #expect(week.steps == 18_000, "Saturday the 19th belongs to last week")
        #expect(week.exerciseMinutes == 120)
        #expect(week.distanceKm == 6.5)
        #expect(week.workouts == 2)
        #expect(week.stepsPerDay == 6_000, "averaged over days with steps")
        #expect(week.days.map(\.active) == [false, true, false, false, false, true, false])
        #expect(week.days.first { $0.isToday }?.date == day(25))
        #expect(week.days.filter(\.isFuture).map(\.date) == [day(26)])
    }

    @Test func followsTheFirstWeekday() {
        var monday = calendar
        monday.firstWeekday = 2
        let week = FitnessWeek(snapshot: FitnessSnapshot(), now: day(20, 12), calendar: monday)
        #expect(week.days.first?.date == day(14), "a Sunday ends a week that starts on Monday")
        #expect(week.days.last?.isToday == true)
        #expect(week.stepsPerDay == 0)
    }
}

@MainActor
struct VO2RatingTests {
    @Test func bandsDependOnAgeAndSex() {
        #expect(VO2Rating.rating(for: 41.9, age: 25, sex: "male") == .fair)
        #expect(VO2Rating.rating(for: 41.9, age: 45, sex: "male") == .good)
        #expect(VO2Rating.rating(for: 41.9, age: 25, sex: "female") == .excellent)
        #expect(VO2Rating.rating(for: 20, age: 70, sex: "female") == .poor)
    }

    @Test func unknownAgeAndSexUseTheMiddle() {
        #expect(VO2Rating.rating(for: 36, age: nil, sex: nil) == .fair)
        #expect(VO2Rating.rating(for: 42, age: nil, sex: nil) == .excellent)
    }
}

// MARK: - Store

private struct FakeFitnessSource: FitnessDataSource {
    var snapshot: FitnessSnapshot
    var isAvailable: Bool { true }
    func snapshot(now: Date, calendar: Calendar) async throws -> FitnessSnapshot { snapshot }
}

private final class FakeCalculator: CalculatorServicing, @unchecked Sendable {
    var weightKg: Double?

    init(weightKg: Double?) { self.weightKg = weightKg }

    func calculator() async throws -> Calculator {
        Calculator(
            biometrics: weightKg.map { .init(weightKg: $0, heightCm: 180, dateOfBirth: "1996-01-01", sex: "male") },
            options: .init(activityLevels: [], goals: [], macroSplits: [])
        )
    }
    func record(_ request: Components.Schemas.BiometricsRequest) async throws -> Calculator { try await calculator() }
    func generate(activityLevel: String, goal: String, split: String) async throws -> Calculator { try await calculator() }
}

@MainActor
struct FitnessStoreTests {
    @Test func loadsHealthAndBodyTogether() async {
        let snapshot = FitnessSnapshot(steps: [DailyValue(day: day(24), value: 3_000), DailyValue(day: day(25), value: 5_000)],
                                       vo2Max: [DailyValue(day: day(20), value: 41.9)])
        let store = FitnessStore(source: FakeFitnessSource(snapshot: snapshot), calculatorService: FakeCalculator(weightKg: 78),
                                 sync: { nil }, now: { day(25, 19) }, calendar: calendar)
        await store.load()

        #expect(store.phase == .ready)
        #expect(store.averageSteps == 4_000)
        #expect(store.weightKg == 78)
        #expect(store.vo2Rating == .good, "30 and male")
        #expect(store.recentSteps.first?.delta == 2_000)
    }

    @Test func emptyHealthIsStillReady() async {
        let store = FitnessStore(source: FakeFitnessSource(snapshot: FitnessSnapshot()), calculatorService: FakeCalculator(weightKg: nil),
                                 sync: { nil }, now: { day(25) }, calendar: calendar)
        await store.load()

        #expect(store.phase == .ready)
        #expect(store.snapshot.isEmpty)
        #expect(store.weightKg == nil)
        #expect(store.vo2Rating == nil)
    }

    @Test func refreshSyncsThenReloads() async {
        let synced = day(25, 18)
        let store = FitnessStore(source: FakeFitnessSource(snapshot: FitnessSnapshot()), calculatorService: FakeCalculator(weightKg: nil),
                                 sync: { synced }, now: { day(25, 19) }, calendar: calendar)
        await store.refresh()

        #expect(store.lastSync == synced)
        #expect(store.syncing == false)
        #expect(store.phase == .ready)
    }
}
