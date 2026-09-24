import Foundation
import NorthAPI
import Testing
import UserNotifications
@testable import khepri

struct WorkoutReminderTests {
    static func plan(_ days: [(String, String?)]) -> PlanDetail {
        PlanDetail(
            id: "plan-1", name: "Base", rationale: "", weeksTotal: 4,
            days: days.map { weekday, start in
                TrainingDay(weekday: weekday, startTime: start, focus: "Full body",
                            exercises: [DayExercise(name: "Goblet squat", sets: 3, reps: "8", restSeconds: 90, equipment: "dumbbell",
                                                    hasArt: true, primaryMuscles: [], secondaryMuscles: [])])
            },
            problems: [], source: .ai, createdAt: .now
        )
    }

    @Test func remindsTheLeadTimeBeforeEachTimedDay() {
        let reminders = WorkoutReminders.reminders(for: Self.plan([("Monday", "07:30"), ("Wednesday", nil), ("Friday", "18:00")]), leadMinutes: 15)
        #expect(reminders.map(\.weekday) == [2, 6])
        #expect(reminders.map { "\($0.hour):\($0.minute)" } == ["7:15", "17:45"])
        #expect(reminders.first?.dayIndex == 0)
        #expect(reminders.last?.dayIndex == 2, "day indices follow the plan, skipped days included")
        #expect(reminders.first?.body == "Starts in 15 minutes, opening with Goblet squat.")
        #expect(reminders.first?.url.absoluteString == "khepri://training/plan-1/0")
    }

    @Test func aLeadAcrossMidnightMovesToTheDayBefore() {
        let reminders = WorkoutReminders.reminders(for: Self.plan([("Sunday", "00:10"), ("Wednesday", "00:05")]), leadMinutes: 30)
        #expect(reminders.map(\.weekday) == [7, 3], "Sunday wraps to Saturday; Wednesday to Tuesday")
        #expect(reminders.map { "\($0.hour):\($0.minute)" } == ["23:40", "23:35"])
    }

    @Test func triggersRepeatWeeklyInTheAccountsTimeZone() throws {
        let lisbon = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let reminder = try #require(WorkoutReminders.reminders(for: Self.plan([("Monday", "07:30")]), leadMinutes: 15).first)
        let request = WorkoutReminders.request(for: reminder, timeZone: lisbon)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.timeZone == lisbon)
        #expect(trigger.dateComponents.weekday == 2 && trigger.dateComponents.hour == 7 && trigger.dateComponents.minute == 15)
        #expect(request.content.categoryIdentifier == WorkoutReminders.categoryIdentifier)
    }

    @Test(arguments: ["Monday", " monday ", "MONDAY"])
    func readsWeekdayNamesLoosely(_ name: String) {
        #expect(WorkoutReminders.weekday(named: name) == 2)
    }

    @Test func ignoresTimesItCannotRead() {
        #expect(WorkoutReminders.clock("25:00") == nil)
        #expect(WorkoutReminders.clock("7pm") == nil)
        #expect(WorkoutReminders.clock("07:05")! == (7, 5))
    }
}
