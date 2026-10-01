import Foundation
import NorthAPI
import Testing
@testable import khepri

struct GlanceTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Wednesday 2026-09-23.
    private let wednesday = Date(timeIntervalSince1970: 1_790_164_800)

    private func day(_ weekday: String, _ focus: String, at time: String? = nil,
                     done: Bool = false, next: Bool = false) -> Components.Schemas.TrainingDay {
        .init(weekday: weekday, startTime: time, focus: focus, exercises: [], completedThisWeek: done, isNext: next)
    }

    @Test func nextIsTheDayTheServerMarks() {
        let next = Glance.nextSession(in: [day("Monday", "Legs"), day("Wednesday", "Upper", at: "07:30", next: true)], now: wednesday, calendar: calendar)
        #expect(next == .init(focus: "Upper", weekday: "Wednesday", startTime: "07:30", isToday: true))
    }

    @Test func nextOnAnotherDayIsNotToday() {
        let next = Glance.nextSession(in: [day("Monday", "Legs", next: true), day("Wednesday", "Upper", done: true)], now: wednesday, calendar: calendar)
        #expect(next == .init(focus: "Legs", weekday: "Monday", startTime: nil, isToday: false))
    }

    @Test func noDayMarkedNextMeansNoSession() {
        #expect(Glance.nextSession(in: [day("Monday", "Legs")], now: wednesday, calendar: calendar) == nil)
    }

    @Test func todaysDayCountsAsDoneOnlyWhenTheServerSaysSo() {
        let open = [day("Wednesday", "Upper"), day("Monday", "Legs", done: true)]
        #expect(Glance.completedToday(in: open, now: wednesday, calendar: calendar) == nil)
        let finished = [day("Wednesday", "Upper", done: true)]
        #expect(Glance.completedToday(in: finished, now: wednesday, calendar: calendar)?.focus == "Upper")
    }

    @Test func completedSummaryAddsTheDurationWhenKnown() {
        var glance = Glance.placeholder
        #expect(glance.completedSummary == nil)
        glance.completedSessionName = "Upper A"
        #expect(glance.completedSummary == "Upper A")
        glance.completedDuration = 52 * 60
        // "52m" in English; the unit word follows the locale.
        #expect(glance.completedSummary?.hasPrefix("Upper A · 52") == true)
    }

    @Test func waterFractionIsCapped() {
        var glance = Glance.placeholder
        glance.waterML = 4000
        #expect(glance.waterFraction == 1)
        glance.waterTargetML = 0
        #expect(glance.waterFraction == 0)
    }
}
