import Foundation
import UserNotifications

/// The Done button under the first week's morning message and its evening
/// note.
///
/// The server sends both with this category; the name has to match
/// `nudges.CategoryCoachFirstWeek`, or the banner arrives without the button.
/// The action is not one of `CoachActions`' answers on purpose: the evening
/// note has no coach message behind it, so Done goes to
/// POST /first-week/done, which works on either.
enum FirstWeekActions {
    static let category = "COACH_FIRST_WEEK"
    static let doneAction = "FIRST_WEEK_DONE"

    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            // Answered in the background: the point is not to have to open the app.
            actions: [UNNotificationAction(
                identifier: doneAction,
                title: String(localized: "Done", comment: "Marks today's first-week action done"),
                options: []
            )],
            intentIdentifiers: []
        )
    }
}
