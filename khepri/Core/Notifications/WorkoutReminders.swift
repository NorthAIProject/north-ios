import Foundation
import NorthAPI
import UserNotifications

/// One weekly "your workout starts soon" reminder.
struct WorkoutReminder: Equatable {
    /// Calendar weekday of the reminder itself, 1 = Sunday … 7 = Saturday.
    var weekday: Int
    var hour: Int
    var minute: Int
    var title: String
    var body: String
    var planID: String
    var dayIndex: Int

    var identifier: String { "\(WorkoutReminders.prefix)\(dayIndex)" }

    /// Where tapping the reminder, or its Start button, goes.
    var url: URL { URL(string: "khepri://training/\(planID)/\(dayIndex)")! }
}

/// Turns a plan's start times into weekly reminders a few minutes before each
/// session, and keeps the system's pending notifications matching them.
///
/// Reminders are local: the phone schedules them from the plan it already has,
/// so they arrive without a push service, offline, and exactly on time.
/// Weekly repeating triggers mean at most seven pending requests, far under
/// iOS's limit of 64, so nothing needs rescheduling as weeks pass; only a
/// changed plan or setting does.
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

    /// Replaces this app's workout reminders with the plan's. Pass nil to
    /// clear them (no plan, or reminders turned off).
    static func schedule(
        _ plan: PlanDetail?,
        timeZone: TimeZone,
        leadMinutes: Int = UserDefaults.standard.object(forKey: leadMinutesKey) as? Int ?? defaultLeadMinutes,
        center: UNUserNotificationCenter = .current()
    ) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard let plan else { return }
        for reminder in reminders(for: plan, leadMinutes: leadMinutes) {
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
        when.weekday = reminder.weekday
        when.hour = reminder.hour
        when.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
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
