import Foundation
import UserNotifications

/// The mood buttons under a "check in with yourself" nudge.
///
/// The server sends those nudges with this category; the name has to match
/// `nudges.CategoryCheckIn` there, or the banner arrives without buttons.
/// A button only picks the mood: it opens today's check-in with that mood
/// already set, and energy is still yours to choose.
enum CheckInActions {
    static let categoryIdentifier = "CHECKIN"
    static let actionPrefix = "CHECKIN_MOOD_"

    /// Titles and the mood each sets, 1 is rough and 5 is great.
    static let moods: [(title: String, mood: Int)] = [("Good", 4), ("Okay", 3), ("Low", 2)]

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: moods.map {
                UNNotificationAction(identifier: "\(actionPrefix)\($0.mood)", title: $0.title, options: [.foreground])
            },
            intentIdentifiers: []
        )
    }

    /// The mood a button stands for, or nil for a plain tap or any other
    /// button.
    static func mood(forAction identifier: String) -> Int? {
        guard identifier.hasPrefix(actionPrefix), let mood = Int(identifier.dropFirst(actionPrefix.count)),
              (1...5).contains(mood) else { return nil }
        return mood
    }

    /// Today's check-in, opened with a mood already chosen.
    static func url(mood: Int) -> URL {
        URL(string: "khepri://check-ins?mood=\(mood)")!
    }
}
