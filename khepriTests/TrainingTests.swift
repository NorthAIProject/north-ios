import Foundation
import NorthAPI
import Testing
import UserNotifications
@testable import khepri

struct WorkoutReminderTests {
    static func plan(_ days: [(String, String?)], completed: Set<String> = [], next: String? = nil) -> PlanDetail {
        PlanDetail(
            id: "plan-1", name: "Base", rationale: "", weeksTotal: 4,
            days: days.map { weekday, start in
                TrainingDay(weekday: weekday, startTime: start, focus: "Full body",
                            exercises: [DayExercise(name: "Goblet squat", sets: 3, reps: "8", restSeconds: 90, equipment: "dumbbell",
                                                    hasArt: true, primaryMuscles: [], secondaryMuscles: [])],
                            completedThisWeek: completed.contains(weekday), isNext: weekday == next)
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

@MainActor
struct TrainingStoreTests {
    @Test func anEditShowsTheVersionItMadeAndReschedules() async {
        let service = FakeTraining()
        var scheduled: [String?] = []
        let store = TrainingStore(service: service, timeZone: { .gmt }, reschedule: { plan, _, _ in scheduled.append(plan?.id) })

        await store.load()
        #expect(store.plan?.id == "v1")

        await store.setStartTime(day: 0, to: "07:00")
        #expect(store.plan?.id == "v2")
        #expect(store.plan?.days.first?.startTime == "07:00")
        #expect(scheduled == ["v1", "v2"], "reminders follow every version shown")
        #expect(store.notice == nil)
    }

    @Test func anEditOnAReplacedVersionShowsTheNewestAndSaysSo() async {
        let service = FakeTraining()
        service.superseded = true
        let store = TrainingStore(service: service, timeZone: { .gmt }, reschedule: { _, _, _ in })

        await store.load()
        await store.setStartTime(day: 0, to: "07:00")
        #expect(store.plan?.id == "newest")
        #expect(store.notice?.contains("another device") == true)
    }

    @Test func noPlansMeansEmptyAndNoReminders() async {
        let service = FakeTraining()
        service.hasPlan = false
        var scheduled: [String?] = ["sentinel"]
        let store = TrainingStore(service: service, timeZone: { .gmt }, reschedule: { plan, _, _ in scheduled = [plan?.id] })

        await store.load()
        #expect(store.phase == .empty)
        #expect(scheduled == [nil])
    }
}

final class FakeTraining: TrainingServicing, @unchecked Sendable {
    var hasPlan = true
    var superseded = false

    static func plan(_ id: String, start: String? = nil) -> PlanDetail {
        WorkoutReminderTests.plan([("Monday", start)]).with(id: id)
    }

    func plans() async throws -> [PlanSummary] {
        hasPlan ? [PlanSummary(id: "v1", name: "Base", weeksTotal: 4, days: [], source: .ai, createdAt: .now)] : []
    }
    func plan(_ id: String) async throws -> PlanDetail { Self.plan(id) }
    func latestIntake() async throws -> TrainingIntake? { nil }
    func createPlan(_ intake: TrainingIntake) async throws -> PlanDetail { Self.plan("new") }
    func setStartTime(plan: String, day: Int, to time: String?) async throws -> PlanEditResult {
        superseded ? .superseded(Self.plan("newest")) : .saved(Self.plan("v2", start: time))
    }
    func addExercise(plan: String, day: Int, slug: String) async throws -> PlanEditResult { .saved(Self.plan(plan)) }
    func swapExercise(plan: String, day: Int, index: Int, slug: String) async throws -> PlanEditResult { .saved(Self.plan(plan)) }
    func removeExercise(plan: String, day: Int, index: Int) async throws -> PlanEditResult { .saved(Self.plan(plan)) }
    func moveExercise(plan: String, day: Int, index: Int, up: Bool) async throws -> PlanEditResult { .saved(Self.plan(plan)) }
    func setPrescription(plan: String, day: Int, index: Int, sets: Int, reps: String, restSeconds: Int) async throws -> PlanEditResult { .saved(Self.plan(plan)) }
    func suggestions(plan: String, day: Int) async throws -> [ExerciseSummary] { [] }
    func replacements(plan: String, day: Int, index: Int) async throws -> [ExerciseSummary] { [] }
    func searchExercises(_ query: String, muscle: String?) async throws -> [ExerciseSummary] { [] }

    var week = TrainingWeek(weekStart: "2026-10-05", custom: false, weekVolume: .hold, days: [])
    private(set) var savedWeeks: [WeekRequest] = []
    private(set) var followed: [String] = []

    func follow(plan: String) async throws -> PlanDetail {
        followed.append(plan)
        return Self.plan(plan)
    }
    func week(next: Bool) async throws -> TrainingWeek { week }
    func setWeek(_ request: WeekRequest, next: Bool) async throws -> TrainingWeek {
        savedWeeks.append(request)
        return week
    }
    func resetWeek(next: Bool) async throws -> TrainingWeek { week }
    func suggestWeek(_ request: WeekRequest, next: Bool) async throws -> WeekSuggestion {
        WeekSuggestion(week: week, matchingPlans: [])
    }
}

extension PlanDetail {
    func with(id: String) -> PlanDetail {
        var copy = self
        copy.id = id
        return copy
    }
}

struct WeekReminderTests {
    static func session(_ date: String, _ weekday: String, start: String?, completed: Bool = false, plan: String = "plan-1") -> WeekSession {
        WeekSession(weekday: weekday, date: date, planId: plan, planName: "Base", dayIndex: 1, focus: "Lower A",
                    startTime: start, exerciseCount: 4, completed: completed, isNext: false)
    }

    @Test func aScheduledWeekRemindsOnItsOwnDatesOnce() throws {
        let lisbon = try #require(TimeZone(identifier: "Europe/Lisbon"))
        // Wednesday 7 October 2026, 08:00 in Lisbon.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-07T07:00:00Z"))
        let week = TrainingWeek(weekStart: "2026-10-05", custom: true, weekVolume: .hold, days: [
            Self.session("2026-10-06", "Tuesday", start: "18:00", completed: true),
            Self.session("2026-10-07", "Wednesday", start: "07:30"),
            Self.session("2026-10-08", "Thursday", start: "18:00"),
            Self.session("2026-10-10", "Saturday", start: nil),
        ])

        let reminders = WorkoutReminders.reminders(for: [week], leadMinutes: 15, timeZone: lisbon, now: now)
        #expect(reminders.count == 1, "done, already past, and untimed sessions get none")
        let reminder = try #require(reminders.first)
        #expect(reminder.date == DateComponents(year: 2026, month: 10, day: 8))
        #expect("\(reminder.hour):\(reminder.minute)" == "17:45")
        #expect(reminder.url.absoluteString == "khepri://training/next", "a week's session may be any plan's")

        let trigger = try #require(WorkoutReminders.request(for: reminder, timeZone: lisbon).trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.day == 8 && trigger.dateComponents.hour == 17)
    }
}

@MainActor
struct TrainingWeekStoreTests {
    @Test func loadingReadsTheWeekAndReschedulesFromIt() async {
        let service = FakeTraining()
        service.week = TrainingWeek(weekStart: "2026-10-05", custom: true, weekVolume: .hold, days: [
            WeekReminderTests.session("2026-10-06", "Tuesday", start: "18:00"),
        ])
        var weeks: [Int] = []
        let store = TrainingStore(service: service, timeZone: { .gmt }, reschedule: { _, scheduled, _ in weeks.append(scheduled.count) })

        await store.load()
        #expect(store.week?.custom == true)
        #expect(weeks == [2], "this week and next")
    }

    @Test func followingAnotherPlanReloads() async {
        let service = FakeTraining()
        let store = TrainingStore(service: service, timeZone: { .gmt }, reschedule: { _, _, _ in })
        await store.load()
        await store.follow("other")
        #expect(service.followed == ["other"])
        #expect(store.phase == .ready)
    }
}

struct DayStatusTests {
    @Test func aFinishedDayReadsCompletedAndNextMovesOn() {
        let plan = WorkoutReminderTests.plan([("Monday", nil), ("Wednesday", nil), ("Friday", nil)],
                                             completed: ["Monday", "Wednesday"], next: "Friday")
        #expect(plan.days.map(\.status) == [.completed, .completed, .next])
        #expect(plan.nextDayIndex == 2)
    }

    @Test func aDayStillOpenCarriesNoMark() {
        let plan = WorkoutReminderTests.plan([("Monday", nil), ("Friday", nil)], next: "Monday")
        #expect(plan.days.map(\.status) == [.next, nil])
    }

    @Test func noNextDayMeansNothingToOpen() {
        let plan = WorkoutReminderTests.plan([("Monday", nil)])
        #expect(plan.nextDayIndex == nil)
    }
}
