import Foundation
import NorthAPI
import Testing
@testable import khepri

struct GoalsTests {
    @Test func aDeadlineTravelsAsACalendarDay() throws {
        var draft = GoalDraft()
        draft.title = "Run a half marathon"
        draft.targetDate = try #require(CalendarDay.date(from: "2026-12-06"))
        #expect(draft.request.targetDate == "2026-12-06")
    }

    @Test func noDeadlineSendsNone() {
        var draft = GoalDraft()
        draft.title = "Read more"
        #expect(draft.request.targetDate == nil)
    }

    @Test func calendarDaysRoundTripInTheDevicesZone() throws {
        let date = try #require(CalendarDay.date(from: "2026-02-28"))
        #expect(CalendarDay.string(from: date) == "2026-02-28")
        #expect(CalendarDay.date(from: "28/02/2026") == nil)
    }
}
