import Foundation
import HealthKit
import NorthAPI
import Testing
@testable import khepri

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hour, minute: minute))!
}

struct HealthPayloadTests {
    @Test func dailyFiguresBecomeDayLongReadingsStartingAtMidnight() {
        let snapshot = HealthSnapshot(steps: [DailyValue(day: day(20), value: 8421)],
                                      restingHeartRate: [DailyValue(day: day(20), value: 52)])
        let requests = HealthPayload.requests(from: snapshot, calendar: utc)

        #expect(requests.count == 1)
        let steps = requests[0].readings?.first { $0.metric == "steps" }
        #expect(steps?.value == 8421)
        #expect(steps?.startedAt == day(20), "the day's start is the server's upsert key")
        #expect(steps?.endedAt == day(21))
        #expect(requests[0].readings?.first { $0.metric == "resting_heart_rate" }?.unit == "count/min")
    }

    @Test func vo2MaxIsSentAsTheServersMetric() {
        let snapshot = HealthSnapshot(vo2Max: [DailyValue(day: day(20), value: 41.9)])
        let reading = HealthPayload.requests(from: snapshot, calendar: utc).first?.readings?.first

        #expect(reading?.metric == "vo2max", "the name the server summarises for the coach")
        #expect(reading?.unit == "ml/kg/min")
        #expect(reading?.value == 41.9)
    }

    @Test func emptyDaysAreNotSent() {
        let snapshot = HealthSnapshot(steps: [DailyValue(day: day(20), value: 0)])
        #expect(HealthPayload.requests(from: snapshot, calendar: utc).isEmpty)
    }

    @Test func manyReadingsAreBatchedWithWorkoutsInTheFirst() {
        let days = (0..<(HealthPayload.batchSize + 10)).map {
            DailyValue(day: utc.date(byAdding: .day, value: -$0, to: day(20))!, value: 100)
        }
        let run = HealthWorkoutRecord(id: UUID(), type: .running, start: day(20, 7), end: day(20, 8),
                                      kilocalories: 500, meters: 10_000, indoor: false)
        let requests = HealthPayload.requests(from: HealthSnapshot(steps: days, workouts: [run]), calendar: utc)

        #expect(requests.count == 2)
        #expect(requests[0].readings?.count == HealthPayload.batchSize)
        #expect(requests[0].workouts?.count == 1)
        #expect(requests[1].workouts?.isEmpty == true)
    }

    @Test func aWorkoutIsTranslatedWithItsOwnIdAndCalories() throws {
        let id = UUID()
        let run = HealthWorkoutRecord(id: id, type: .running, start: day(20, 7), end: day(20, 8),
                                      kilocalories: 612, meters: 10_000, indoor: false)
        let payload = try #require(HealthPayload.workout(run))
        #expect(payload.activityCode == "running_9_8kmh", "10 km in an hour")
        #expect(payload.externalId == id.uuidString)
        #expect(payload.calories == 612)
    }

    @Test func aWorkoutCarriesWhatTheWatchMeasured() throws {
        var run = HealthWorkoutRecord(id: UUID(), type: .running, start: day(20, 7), end: day(20, 8),
                                      kilocalories: 612, meters: 10_000, indoor: true)
        run.averageHeartRate = 151
        run.maximumHeartRate = 177
        run.elevationAscended = 0 // nothing climbed: not measured, so not sent
        let payload = try #require(HealthPayload.workout(run))
        #expect(payload.distanceM == 10_000 && payload.avgHeartRate == 151 && payload.maxHeartRate == 177)
        #expect(payload.elevationM == nil && payload.indoor == true)
    }

    @Test func aWorkoutThatDoesNotSayWhereSendsNoIndoorFlag() throws {
        let run = HealthWorkoutRecord(id: UUID(), type: .running, start: day(20, 7), end: day(20, 8),
                                      kilocalories: nil, meters: 10_000, indoor: nil)
        let payload = try #require(HealthPayload.workout(run))
        #expect(payload.indoor == nil && payload.avgHeartRate == nil)
    }

    @Test func theNewerTypesAreSentUnderTheServersNames() {
        var snapshot = HealthSnapshot()
        snapshot.walkingRunningKm = [DailyValue(day: day(20), value: 6.4)]
        snapshot.flightsClimbed = [DailyValue(day: day(20), value: 12)]
        snapshot.mindfulMinutes = [DailyValue(day: day(20), value: 10)]
        snapshot.walkingHeartRate = [DailyValue(day: day(20), value: 102)]
        snapshot.respiratoryRate = [DailyValue(day: day(20), value: 14.2)]
        snapshot.bloodOxygen = [DailyValue(day: day(20), value: 0.968)]
        let readings = HealthPayload.requests(from: snapshot, calendar: utc).first?.readings ?? []
        let byMetric = Dictionary(uniqueKeysWithValues: readings.map { ($0.metric, $0) })
        #expect(byMetric["distance_walking_running"]?.value == 6.4 && byMetric["distance_walking_running"]?.unit == "km")
        #expect(byMetric["flights_climbed"]?.value == 12 && byMetric["mindful_minutes"]?.value == 10)
        #expect(byMetric["walking_hr_avg"]?.value == 102 && byMetric["respiratory_rate"]?.value == 14.2)
        #expect(byMetric["spo2"]?.value == 96.8 && byMetric["spo2"]?.unit == "%", "a fraction sent as a percentage")
    }

    @Test func overlappingMindfulSessionsCountOnce() {
        let sit = DateInterval(start: day(20, 7), duration: 600)
        let sameSitFromAnotherApp = DateInterval(start: day(20, 7, 2), duration: 600)
        let evening = DateInterval(start: day(20, 21), duration: 300)
        let minutes = MindfulDays.minutes([sit, sameSitFromAnotherApp, evening], calendar: utc)
        #expect(minutes == [DailyValue(day: day(20), value: 17)])
    }

    @Test func aWorkoutNorthCannotNameIsLeftOut() {
        let fishing = HealthWorkoutRecord(id: UUID(), type: .fishing, start: day(20, 7), end: day(20, 9),
                                          kilocalories: nil, meters: nil, indoor: false)
        #expect(HealthPayload.workout(fishing) == nil)
    }
}

struct HealthActivityMappingTests {
    @Test(arguments: [(7.5, "running_8kmh"), (10.0, "running_9_8kmh"), (12.0, "running_11_3kmh"), (14.0, "running_fast")])
    func runningIsGradedBySpeed(_ kmh: Double, _ code: String) {
        #expect(HealthActivityMapping.code(for: .running, kmh: kmh, indoor: false) == code)
    }

    @Test func indoorCyclingIsStationary() {
        #expect(HealthActivityMapping.code(for: .cycling, kmh: 30, indoor: true) == "cycling_stationary_moderate")
        #expect(HealthActivityMapping.code(for: .cycling, kmh: 20, indoor: false) == "cycling_vigorous")
    }

    @Test func noDistanceFallsBackToTheMiddleGrade() {
        #expect(HealthActivityMapping.code(for: .walking, kmh: nil, indoor: false) == "walking_moderate")
        #expect(HealthActivityMapping.code(for: .traditionalStrengthTraining, kmh: nil, indoor: true) == "strength_training")
    }
}

struct SleepNightsTests {
    @Test func overlappingDevicesCountTheNightOnce() {
        let watch = DateInterval(start: day(19, 23), end: day(20, 7))
        let phone = DateInterval(start: day(20, 0), end: day(20, 6, 30))
        let nights = SleepNights.minutes(asleep: [watch, phone], calendar: utc)
        #expect(nights == [DailyValue(day: day(20), value: 480)])
    }

    @Test func aNightBelongsToTheMorningItEnds() {
        let nap = DateInterval(start: day(20, 14), end: day(20, 14, 30))
        let night = DateInterval(start: day(20, 23), end: day(21, 6))
        let nights = SleepNights.minutes(asleep: [nap, night], calendar: utc)
        #expect(nights == [DailyValue(day: day(20), value: 30), DailyValue(day: day(21), value: 420)])
    }
}

struct HealthSyncTests {
    @Test func firstSyncReadsAMonthThenEachSyncRereadsTwoDays() async throws {
        let source = FakeHealthSource()
        let defaults = UserDefaults.ephemeral()
        let sync = HealthSync(source: source, uploader: FakeUploader(), defaults: defaults, now: { day(20, 12) })
        sync.setEnabled(true)

        _ = try await sync.syncIfEnabled(calendar: utc)
        #expect(await source.starts == [day(20 - HealthSync.firstSyncDays)])

        _ = try await sync.syncIfEnabled(calendar: utc)
        #expect(await source.starts.last == day(18), "two days before the last sync, for late watch data")
    }

    // An install that synced before workouts carried heart rate re-reads 90
    // days once, so those sessions get it; after that, the usual two days.
    @Test func anOlderInstallBackfillsWorkoutsOnce() async throws {
        let source = FakeHealthSource()
        let defaults = UserDefaults.ephemeral()
        let earlier = HealthSyncReport(at: day(19, 12), readings: 10, workouts: 1)
        defaults.set(try JSONEncoder().encode(earlier), forKey: HealthSync.lastReportKey)
        let sync = HealthSync(source: source, uploader: FakeUploader(), defaults: defaults, now: { day(20, 12) })
        sync.setEnabled(true)

        _ = try await sync.syncIfEnabled(calendar: utc)
        #expect(await source.starts == [utc.date(byAdding: .day, value: -HealthSync.backfillDays, to: day(20))!])

        _ = try await sync.syncIfEnabled(calendar: utc)
        #expect(await source.starts.last == day(18))
    }

    @Test func offMeansNothingRuns() async throws {
        let source = FakeHealthSource()
        let sync = HealthSync(source: source, uploader: FakeUploader(), defaults: .ephemeral())
        #expect(try await sync.syncIfEnabled(calendar: utc) == nil)
        #expect(await source.starts.isEmpty)
    }

    @Test func theReportAddsUpEveryBatch() async throws {
        let source = FakeHealthSource(snapshot: HealthSnapshot(steps: [DailyValue(day: day(20), value: 1000)]))
        let uploader = FakeUploader()
        let sync = HealthSync(source: source, uploader: uploader, defaults: .ephemeral(), now: { day(20, 12) })
        sync.setEnabled(true)

        let report = try #require(try await sync.syncIfEnabled(calendar: utc))
        #expect(report.readings == 1)
        #expect(sync.lastReport == report)
    }

    @Test func disconnectingForgetsOnTheServerAndStops() async throws {
        let uploader = FakeUploader()
        let sync = HealthSync(source: FakeHealthSource(), uploader: uploader, defaults: .ephemeral())
        sync.setEnabled(true)

        try await sync.disconnect()

        #expect(await uploader.forgot)
        #expect(!sync.isEnabled)
        #expect(sync.lastReport == nil)
    }
}

struct StravaConnectResultTests {
    @Test(arguments: [("connected", StravaConnectResult.connected), ("cancelled", .cancelled),
                      ("expired", .expired), ("nonsense", .failed)])
    func readsTheServersVerdict(_ result: String, _ expected: StravaConnectResult) throws {
        let url = try #require(URL(string: "khepri://fitness/strava?result=\(result)"))
        #expect(StravaConnectResult(callback: url) == expected)
    }
}

@MainActor
struct WorkoutHealthTests {
    @Test func finishingSavesTheWorkoutToAppleHealth() async {
        let clock = TestClock()
        let writer = FakeHealthWriter()
        let day = TrainingDay(weekday: "Monday", focus: "Full body", exercises: [
            DayExercise(name: "Push-up", sets: 1, reps: "10", restSeconds: 0, equipment: "none",
                        hasArt: false, primaryMuscles: [], secondaryMuscles: []),
        ], completedThisWeek: false, isNext: true)
        let session = WorkoutSession(title: "Monday", day: day, service: FakeActivity(), live: FakeLiveActivity(),
                                     health: writer, now: { clock.now })
        session.start()
        clock.advance(600)
        await session.completeSet()

        #expect(await writer.saved.count == 1)
        #expect(await writer.saved.first?.duration == 600)
    }
}

// MARK: - Fakes

actor FakeHealthSource: HealthDataSource {
    private(set) var starts: [Date] = []
    private let result: HealthSnapshot

    init(snapshot: HealthSnapshot = HealthSnapshot()) { result = snapshot }

    nonisolated var isAvailable: Bool { true }

    func snapshot(from start: Date, to end: Date, calendar: Calendar) async throws -> HealthSnapshot {
        starts.append(start)
        return result
    }
}

actor FakeUploader: HealthUploading {
    private(set) var forgot = false

    func sync(_ request: HealthSyncRequest) async throws -> Components.Schemas.HealthSyncResult {
        .init(readings: request.readings?.count ?? 0, workouts: request.workouts?.count ?? 0)
    }

    func forget() async throws { forgot = true }
}

actor FakeHealthWriter: HealthWorkoutWriting {
    private(set) var saved: [DateInterval] = []

    func saveStrengthWorkout(start: Date, end: Date) async {
        saved.append(DateInterval(start: start, end: end))
    }
}

struct MyDayHealthTests {
    @Test func stagesComeFromTheSourceThatRecordedMostAndJoinUp() {
        let watch = "com.apple.health.watch", phone = "com.example.sleepapp"
        let samples: [SleepStages.Sample] = [
            .init(stage: .core, start: day(19, 23), end: day(20, 1), source: watch),
            .init(stage: .core, start: day(20, 1), end: day(20, 2), source: watch),
            .init(stage: .deep, start: day(20, 2), end: day(20, 3), source: watch),
            .init(stage: .awake, start: day(20, 3), end: day(20, 3, 10), source: watch),
            .init(stage: .rem, start: day(20, 0), end: day(20, 1), source: phone),
        ]
        let blocks = SleepStages.blocks(from: samples, calendar: utc)
        #expect(blocks.map(\.stage) == [.core, .deep, .awake], "the phone's REM is dropped, the two core blocks join")
        #expect(blocks.first == SleepStageBlock(stage: .core, start: day(19, 23), end: day(20, 2)))
    }

    @Test func stagesAndDayTotalsBecomeReadings() {
        var snapshot = HealthSnapshot()
        snapshot.sleepStages = [SleepStageBlock(stage: .deep, start: day(20, 1), end: day(20, 2, 30))]
        snapshot.daylightMinutes = [DailyValue(day: day(20), value: 84)]
        snapshot.dietaryWater = [DailyValue(day: day(20), value: 250)]
        snapshot.bodyMass = [DailyValue(day: day(20), value: 83.9)]
        let readings = HealthPayload.requests(from: snapshot, calendar: utc).first?.readings ?? []

        let deep = readings.first { $0.metric == "sleep_deep" }
        #expect(deep?.value == 90)
        #expect(deep?.startedAt == day(20, 1) && deep?.endedAt == day(20, 2, 30))
        #expect(readings.first { $0.metric == "time_in_daylight" }?.endedAt == day(21))
        #expect(readings.first { $0.metric == "dietary_water" }?.unit == "ml")
        let weight = readings.first { $0.metric == "body_mass" }
        #expect(weight?.value == 83.9 && weight?.endedAt == nil, "a weighing is an instant")
    }

    @Test func onlyStagedValuesHaveAStage() {
        #expect(SleepStages.stage(for: HKCategoryValueSleepAnalysis.asleepDeep.rawValue) == .deep)
        #expect(SleepStages.stage(for: HKCategoryValueSleepAnalysis.inBed.rawValue) == nil)
        #expect(SleepStages.stage(for: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue) == nil)
    }
}

struct MyDayHealthPhaseTwoTests {
    @Test func bloodPressureBecomesTwoInstantReadings() {
        var snapshot = HealthSnapshot()
        snapshot.bloodPressure = [BloodPressureReading(at: day(20, 8), systolic: 122, diastolic: 79)]
        snapshot.vitaminD = [DailyValue(day: day(20), value: 10)]
        let readings = HealthPayload.requests(from: snapshot, calendar: utc).first?.readings ?? []
        #expect(readings.first { $0.metric == "bp_systolic" }?.value == 122)
        #expect(readings.first { $0.metric == "bp_diastolic" }?.startedAt == day(20, 8))
        #expect(readings.first { $0.metric == "dietary_vitamin_d" }?.unit == "mcg")
    }
}
