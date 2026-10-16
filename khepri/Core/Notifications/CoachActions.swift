import Foundation
import UserNotifications

/// The answers under the coach's unprompted message: Undo for a session it
/// lightened on a low-recovery morning, and Today / Tomorrow / Let it go for a
/// session missed yesterday.
///
/// The server sends those messages with these categories; the names have to
/// match `nudges.CategoryCoachLighter` and `nudges.CategoryCoachMissed`, or the
/// banner arrives without buttons. The action identifiers end in the answer the
/// server expects, so a tap is answered without opening the app.
enum CoachActions {
    static let lighterCategory = "COACH_LIGHTER"
    static let missedCategory = "COACH_MISSED"
    static let actionPrefix = "COACH_ANSWER_"

    static var categories: [UNNotificationCategory] {
        [
            UNNotificationCategory(
                identifier: lighterCategory,
                actions: [action("undo", String(localized: "Undo", comment: "Button on the coach's notification that put back a session it lightened"))],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: missedCategory,
                actions: [
                    action("today", String(localized: "Do It Today", comment: "Button on the coach's notification about a missed session")),
                    action("tomorrow", String(localized: "Tomorrow", comment: "Button on the coach's notification about a missed session")),
                    action("let_go", String(localized: "Let It Go", comment: "Button on the coach's notification about a missed session")),
                ],
                intentIdentifiers: []
            ),
        ]
    }

    /// The answer a button stands for, or nil for a plain tap or any other
    /// button. A button the server did not offer today (say Tomorrow, when
    /// tomorrow has its own session) is refused by the server, harmlessly.
    static func answer(forAction identifier: String) -> String? {
        guard identifier.hasPrefix(actionPrefix) else { return nil }
        let answer = String(identifier.dropFirst(actionPrefix.count))
        return answer.isEmpty ? nil : answer
    }

    private static func action(_ answer: String, _ title: String) -> UNNotificationAction {
        // Answered in the background: the point is not to have to open the app.
        UNNotificationAction(identifier: actionPrefix + answer, title: title, options: [])
    }
}
