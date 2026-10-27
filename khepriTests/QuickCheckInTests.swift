import Foundation
import NorthAPI
import Testing
@testable import khepri

struct QuickCheckInStepTests {
    private let picked = Date(timeIntervalSince1970: 1_793_000_000) // a weekday, mid-morning UTC

    private func store(at date: @escaping @Sendable () -> Date) -> QuickCheckInStep {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return QuickCheckInStep(defaults: UserDefaults(suiteName: UUID().uuidString)!, now: date, calendar: calendar)
    }

    @Test func theFirstTapIsHeldForTheSecond() {
        let step = store { picked }
        step.pick(4)
        #expect(step.pendingMood == 4)
        step.clear()
        #expect(step.pendingMood == nil)
    }

    @Test func aPickLapsesAfterTenMinutes() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        QuickCheckInStep(defaults: defaults, now: { picked }, calendar: calendar).pick(4)
        let soon = QuickCheckInStep(defaults: defaults, now: { picked.addingTimeInterval(9 * 60) }, calendar: calendar)
        let late = QuickCheckInStep(defaults: defaults, now: { picked.addingTimeInterval(11 * 60) }, calendar: calendar)
        #expect(soon.pendingMood == 4)
        #expect(late.pendingMood == nil)
        #expect(soon.expiry == picked.addingTimeInterval(10 * 60))
    }

    /// A mood picked for one day is not filed for the next.
    @Test func aPickLapsesAtMidnight() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let beforeMidnight = try #require(calendar.date(bySettingHour: 23, minute: 58, second: 0, of: picked))
        QuickCheckInStep(defaults: defaults, now: { beforeMidnight }, calendar: calendar).pick(3)
        let afterMidnight = beforeMidnight.addingTimeInterval(4 * 60)
        let after = QuickCheckInStep(defaults: defaults, now: { afterMidnight }, calendar: calendar)
        #expect(after.pendingMood == nil)
    }
}

struct QuickCheckInFilerTests {
    actor Saves {
        var requests: [CheckInRequest] = []
        func add(_ request: CheckInRequest) { requests.append(request) }
    }

    private static func saved() -> SavedCheckIn {
        SavedCheckIn(
            value1: CheckIn(id: "c1", localDate: "2026-10-27", mood: 4, energy: 2, wins: "", challenges: "", notes: "",
                            updatedAt: .now, createdAt: .now, source: "widget", tags: []),
            value2: .init(created: true, streak: 8, restDaysHeld: 1, perfectWeek: false)
        )
    }

    /// A save replaces every field of today's check-in, so two taps over one
    /// written in the app would wipe its notes. The quick path refuses.
    @Test func itNeverFilesOverTodaysCheckIn() async throws {
        let saves = Saves()
        let filer = QuickCheckInFiler(source: "widget", hasToday: { true }, save: { request in
            await saves.add(request)
            return Self.saved()
        })
        #expect(try await filer.file(mood: 4, energy: 2) == .alreadyCheckedIn)
        #expect(await saves.requests.isEmpty)
    }

    @Test func itFilesMoodEnergyAndTheSurface() async throws {
        let saves = Saves()
        let filer = QuickCheckInFiler(source: "notification", hasToday: { false }, save: { request in
            await saves.add(request)
            return Self.saved()
        })
        #expect(try await filer.file(mood: 4, energy: 2) == .filed(streak: 8, momentTitle: nil))
        let request = try #require(await saves.requests.first)
        #expect(request.mood == 4 && request.energy == 2 && request.source == "notification")
    }
}
