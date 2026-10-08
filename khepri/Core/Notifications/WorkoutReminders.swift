import Foundation
import NorthAPI
import UserNotifications

/// One "your workout starts soon" reminder: weekly from the plan's own days,
/// or once, on a date, from a week the server scheduled.
struct WorkoutReminder: Equatable {
    /// Calendar weekday of the reminder itself, 1 = Sunday … 7 = Saturday.
    var weekday: Int
    var hour: Int
    var minute: Int
    var title: String
    var body: String
    var planID: String
    var dayIndex: Int
    /// The reminder's own calendar date, for a one-off; nil repeats weekly.
    var date: DateComponents?

    var identifier: String {
        if let date, let year = date.year, let month = date.month, let day = date.day {
            return String(format: "\(WorkoutReminders.prefix)%04d-%02d-%02d", year, month, day)
        }
        return "\(WorkoutReminders.prefix)\(dayIndex)"
    }

    /// Where tapping the reminder goes. A dated reminder is for the week's
    /// next session, which may be any plan's, so it opens that rather than a
    /// day of the followed plan.
    var url: URL {
        date == nil ? URL(string: "khepri://training/\(planID)/\(dayIndex)")! : URL(string: "khepri://training/next")!
    }
}

/// Turns a plan's start times into weekly reminders a few minutes before each
/// session, and keeps the system's pending notifications matching them.
///
/// Reminders are local: the phone schedules them from what it already has, so
/// they arrive without a push service, offline, and exactly on time. From the
/// server's weeks they are dated, at most fourteen for two weeks, far under
/// iOS's limit of 64; from a plan alone they repeat weekly.
enum WorkoutReminders {
    static let prefix = "workout.reminder."
    static let categoryIdentifier = "WORKOUT_REMINDER"
    static let startActionIdentifier = "START_WORKOUT"

    /// Lead time is stored on the device: how soon before a session to say so.
    static let leadMinutesKey = "workoutReminders.leadMinutes"
    static let defaultLeadMinutes = 15

    /// The reminders for a plan. Days with no start time, or a weekday this
    /// cannot read, get none.
    static func reminders(for plan: PlanDetail, leadMinutes: Int) -> [WorkoutReminder] {
        plan.days.enumerated().compactMap { index, day in
            guard let start = day.startTime, let weekday = weekday(named: day.weekday),
                  let (hour, minute) = clock(start) else { return nil }

            // Subtracting the lead can cross midnight into the day before.
            var total = hour * 60 + minute - max(0, leadMinutes)
            var remindWeekday = weekday
            if total < 0 {
                total += 24 * 60
                remindWeekday = weekday == 1 ? 7 : weekday - 1
            }

            let exercise = day.exercises.first?.name
            return WorkoutReminder(
                weekday: remindWeekday,
                hour: total / 60,
                minute: total % 60,
                title: "\(day.focus) at \(start)",
                body: leadMinutes > 0
                    ? "Starts in \(leadMinutes) minutes\(exercise.map { ", opening with \($0)" } ?? "")."
                    : "Starting now\(exercise.map { ", opening with \($0)" } ?? "").",
                planID: plan.id,
                dayIndex: index
            )
        }
    }

    /// The reminders for the weeks the server scheduled: one for each
    /// session still to come that has a start time. A week can move sessions
    /// off the plan's own days, so these are dated rather than weekly; the
    /// app reschedules them whenever Training loads, two weeks ahead.
    static func reminders(for weeks: [TrainingWeek], leadMinutes: Int, timeZone: TimeZone, now: Date = .now) -> [WorkoutReminder] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parse = DateFormatter()
        parse.calendar = calendar
        parse.timeZone = timeZone
        parse.dateFormat = "yyyy-MM-dd"

        return weeks.flatMap(\.days).compactMap { session in
            guard !session.completed, let start = session.startTime, let (hour, minute) = clock(start),
                  let day = parse.date(from: session.date),
                  let starts = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            let remind = starts.addingTimeInterval(TimeInterval(-max(0, leadMinutes) * 60))
            guard remind > now else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: remind)
            return WorkoutReminder(
                weekday: parts.weekday ?? 1,
                hour: parts.hour ?? hour,
                minute: parts.minute ?? minute,
                title: "\(session.focus) at \(start)",
                body: leadMinutes > 0 ? "Starts in \(leadMinutes) minutes." : "Starting now.",
                planID: session.planId,
                dayIndex: session.dayIndex,
                date: DateComponents(year: parts.year, month: parts.month, day: parts.day)
            )
        }
    }

    /// Replaces this app's workout reminders. With the weeks the server
    /// scheduled they follow those; without, the plan's own days, weekly.
    /// Pass a nil plan to clear them (no plan, or reminders turned off).
    static func schedule(
        _ plan: PlanDetail?,
        weeks: [TrainingWeek] = [],
        timeZone: TimeZone,
        leadMinutes: Int = UserDefaults.standard.object(forKey: leadMinutesKey) as? Int ?? defaultLeadMinutes,
        center: UNUserNotificationCenter = .current()
    ) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard let plan else { return }
        let planned = weeks.isEmpty
            ? reminders(for: plan, leadMinutes: leadMinutes)
            : reminders(for: weeks, leadMinutes: leadMinutes, timeZone: timeZone)
        for reminder in planned {
            try? await center.add(request(for: reminder, timeZone: timeZone))
        }
    }

    static func request(for reminder: WorkoutReminder, timeZone: TimeZone) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["url": reminder.url.absoluteString]
        content.interruptionLevel = .timeSensitive

        // In the account's time zone, so a session planned for 07:00 at home
        // is still announced at home-07:00 while travelling, matching the web
        // and the coach, which both read the account's zone.
        var when = DateComponents()
        when.timeZone = timeZone
        if let date = reminder.date {
            when.year = date.year
            when.month = date.month
            when.day = date.day
        } else {
            when.weekday = reminder.weekday
        }
        when.hour = reminder.hour
        when.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: reminder.date == nil)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    /// The "Start Workout" button on the reminder, which opens the app.
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [UNNotificationAction(identifier: startActionIdentifier, title: "Start Workout", options: [.foreground])],
            intentIdentifiers: []
        )
    }

    /// English weekday names, as the server writes them, to calendar weekdays.
    static func weekday(named name: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return names.firstIndex(of: name.trimmingCharacters(in: .whitespaces).lowercased()).map { $0 + 1 }
    }

    /// "07:30" → (7, 30)
    static func clock(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}
