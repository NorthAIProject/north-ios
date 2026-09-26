import Foundation
import NorthAPI
import Testing
@testable import khepri

private func response(date: String = "2026-09-26", isToday: Bool = true) -> DayResponse {
    let now = Date(timeIntervalSince1970: 1_790_444_760) // 2026-09-26 14:46 UTC
    let hour: (Double) -> Date = { now.addingTimeInterval($0 * 3600) }
    return DayResponse(
        date: date, isToday: isToday, now: now,
        vitals: .init(energyPercent: 32, daylightMinutes: 84),
        food: .init(calories: 1750, proteinG: 80, carbG: 110, fatG: 90, goal: .init(calories: 2200, proteinG: 160, carbG: 220, fatG: 60)),
        water: .init(totalMl: 1550, targetMl: 2500),
        activity: .init(move: .init(value: 250, goal: 500, percent: 50),
                        exercise: .init(value: 62, goal: 30, percent: 207),
                        stand: .init(value: 0, goal: 12, percent: 0)),
        sleep: .init(totalMinutes: 433, stages: .init(additionalProperties: ["deep": 60]),
                     blocks: [.init(stage: .core, start: hour(-10), end: hour(-9)),
                              .init(stage: .awake, start: hour(-9), end: hour(-8))],
                     source: "apple_health"),
        workouts: .init(count: 0, minutes: 0, calories: 0, labels: []),
        body: .init(soreness: []),
        streak: 9,
        level: 2,
        caffeine: .init(totalMg: 100, activeMg: 72, limitMg: 400, afterCutoff: false),
        nutrients: .init(covered: ["omega3"], missing: ["iron"], total: 2),
        milestones: [],
        timeline: [.init(kind: "food", at: hour(-1), title: "Lunch", icon: "utensils"),
                   .init(kind: "hydration", at: hour(1), title: "Water", icon: "droplet")],
        markers: [.init(kind: "kitchen_closes", label: "Kitchen closes", at: hour(5), passed: false)]
    )
}

actor FakeDayService: DayServicing {
    private(set) var asked: [String?] = []
    var fail = false

    func day(_ date: String?) async throws -> DayResponse {
        asked.append(date)
        if fail { throw URLError(.notConnectedToInternet) }
        return response(date: date ?? "2026-09-26", isToday: date == nil)
    }

    func failNext() { fail = true }

    func trends() async throws -> DayTrends {
        DayTrends(series: [], fasts: [])
    }
}

@MainActor
struct DayStoreTests {
    @Test func todayAsksWithoutADateAndSteppingSendsOne() async throws {
        let service = FakeDayService()
        let store = DayStore(service: service)
        await store.load()
        #expect(store.isToday)

        await store.step(-1)
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)))
        #expect(await service.asked == [nil, CalendarDay.string(from: yesterday)])
        #expect(!store.isToday)

        await store.step(1)
        #expect(await service.asked.last == .some(nil), "stepping back onto today follows today again")
    }

    @Test func aFailedRefreshKeepsTheDayOnScreen() async {
        let service = FakeDayService()
        let store = DayStore(service: service)
        await store.load()
        await service.failNext()
        await store.load()
        #expect(store.day != nil)
        #expect(store.error == nil)
    }

    @Test func aFailedFirstLoadSaysWhy() async {
        let service = FakeDayService()
        await service.failNext()
        let store = DayStore(service: service)
        await store.load()
        #expect(store.day == nil)
        #expect(store.error != nil)
    }
}

struct DayMathTests {
    @Test func ringsCapAtFullAndReadEmptyWithoutAGoal() {
        let day = response()
        let rings = DayMath.activityRings(day.activity)
        #expect(rings.map(\.fraction) == [0.5, 1, 0])
        #expect(DayMath.fraction(10, 0) == 0)
        #expect(DayMath.macroRings(day.food).map(\.fraction) == [0.5, 0.5, 1])
    }

    @Test func theTimelineReadsLatestFirstWithNowAndMarkersInPlace() {
        let rows = DayMath.timeline(response())
        let ids = rows.map(\.id)
        #expect(ids == ["m0", "e1", "now", "e0"])
        #expect(DayMath.timeline(response(isToday: false)).allSatisfy { $0.id != "now" })
    }

    @Test func theHypnogramSpansTheNight() throws {
        let blocks = DayMath.hypnogram(try #require(response().sleep))
        #expect(blocks.map(\.start) == [0, 0.5])
        #expect(blocks.map(\.width) == [0.5, 0.5])
        #expect(blocks.map(\.row) == [2, 0], "core sits two rows down, awake on top")
    }

    @Test func durationsReadLikeTheWeb() {
        #expect(DayMath.duration(433) == "7h 13m")
        #expect(DayMath.duration(45) == "45m")
    }
}

actor RecordingActions: DayActing {
    private(set) var calls: [String] = []
    func logWater(_ ml: Int) async throws { calls.append("water \(ml)") }
    func logCaffeine(preset: String) async throws { calls.append("caffeine \(preset)") }
    func logSupplement(preset: String, count: Int) async throws { calls.append("supplement \(preset) \(count)") }
    func startFast(hours: Int) async throws { calls.append("fast \(hours)") }
    func stopFast() async throws { throw URLError(.badServerResponse) }
    func setScreenTime(minutes: Int) async throws { calls.append("screen \(minutes)") }
    func setSoreness(region: String, severity: Int) async throws { calls.append("sore \(region) \(severity)") }
    func clearSoreness(region: String) async throws { calls.append("clear \(region)") }
    func recordBloodPressure(systolic: Int, diastolic: Int) async throws { calls.append("bp \(systolic)/\(diastolic)") }
    func setTargetWeight(_ kg: Double?) async throws { calls.append("target \(kg ?? 0)") }
    func createTracker(name: String, lastDone: Date?) async throws { calls.append("tracker \(name)") }
    func trackerDone(id: String) async throws { calls.append("done \(id)") }
}

@MainActor
struct DayActionTests {
    @Test func aWriteReloadsTheDay() async {
        let service = FakeDayService()
        let actions = RecordingActions()
        let store = DayStore(service: service, actions: actions)
        await store.perform { try await $0.logCaffeine(preset: "coffee") }
        #expect(await actions.calls == ["caffeine coffee"])
        #expect(await service.asked.count == 1, "the day reloads after the write")
        #expect(store.actionError == nil)
    }

    @Test func aFailedWriteSaysWhyAndStillReloads() async {
        let service = FakeDayService()
        let store = DayStore(service: service, actions: RecordingActions())
        await store.perform { try await $0.stopFast() }
        #expect(store.actionError != nil)
        #expect(await service.asked.count == 1)
    }
}

struct DayNamesTests {
    @Test func everyRegionTheServerKnowsHasAName() {
        let server = ["neck", "shoulders", "chest", "upper_back", "lower_back", "abs", "biceps", "triceps",
                      "forearms", "hips", "glutes", "quads", "hamstrings", "knees", "calves", "feet"]
        #expect(DayMath.regions.map(\.key) == server)
        #expect(DayMath.clock(766) == "12:46")
        #expect(DayMath.nutrientName("omega3") == "Omega-3")
    }
}
