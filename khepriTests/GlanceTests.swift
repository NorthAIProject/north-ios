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

    private func day(_ weekday: String, _ focus: String, at time: String? = nil) -> Components.Schemas.DaySummary {
        .init(weekday: weekday, startTime: time, focus: focus, exerciseCount: 5)
    }

    @Test func todaysSessionComesFirst() {
        let next = Glance.nextSession(in: [day("Monday", "Legs"), day("Wednesday", "Upper", at: "07:30")], now: wednesday, calendar: calendar)
        #expect(next == .init(focus: "Upper", weekday: "Wednesday", startTime: "07:30", isToday: true))
    }

    @Test func otherwiseTheNextDayAheadWrappingTheWeek() {
        let next = Glance.nextSession(in: [day("Monday", "Legs"), day("Tuesday", "Push")], now: wednesday, calendar: calendar)
        #expect(next?.focus == "Legs")
        #expect(next?.isToday == false)
    }

    @Test func noRecognisableDayMeansNoSession() {
        #expect(Glance.nextSession(in: [day("Someday", "?")], now: wednesday, calendar: calendar) == nil)
    }

    @Test func waterFractionIsCapped() {
        var glance = Glance.placeholder
        glance.waterML = 4000
        #expect(glance.waterFraction == 1)
        glance.waterTargetML = 0
        #expect(glance.waterFraction == 0)
    }
}
