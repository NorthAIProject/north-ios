import Foundation
import UserNotifications
import WidgetKit

/// The buttons under a check-in nudge: two taps, a mood and then an energy,
/// file today's check-in without opening the app.
///
/// The server sends those nudges with `categoryIdentifier`; the name has to
/// match `nudges.CategoryCheckIn` there, or the banner arrives without
/// buttons. A mood button posts a second, local banner in the same thread
/// asking for energy; the server never sees `energyCategoryIdentifier`. The
/// mood and the day travel in that banner, so nothing is stored between the
/// taps.
enum CheckInActions {
    static let categoryIdentifier = "CHECKIN"
    static let actionPrefix = "CHECKIN_MOOD_"
    static let energyCategoryIdentifier = "CHECKIN_ENERGY"
    static let energyActionPrefix = "CHECKIN_ENERGY_"
    static let moodKey = "quickCheckInMood"
    static let dayKey = "quickCheckInDay"

    /// Titles and the mood each sets, 1 is rough and 5 is great.
    static var moods: [(title: String, mood: Int)] {
        [
            (String(localized: "Good", comment: "Mood button on a check-in notification"), 4),
            (String(localized: "Okay", comment: "Mood button on a check-in notification"), 3),
            (String(localized: "Low", comment: "Mood button on a check-in notification"), 2),
        ]
    }

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: moods.map {
                UNNotificationAction(identifier: "\(actionPrefix)\($0.mood)", title: $0.title, options: [])
            },
            intentIdentifiers: []
        )
    }

    static var energyCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: energyCategoryIdentifier,
            actions: QuickCheckIn.energies.reversed().map {
                UNNotificationAction(
                    identifier: "\(energyActionPrefix)\($0.value)", title: String(localized: $0.title), options: []
                )
            },
            intentIdentifiers: []
        )
    }

    /// The mood a button stands for, or nil for a plain tap or any other
    /// button.
    static func mood(forAction identifier: String) -> Int? {
        value(identifier, prefix: actionPrefix)
    }

    static func energy(forAction identifier: String) -> Int? {
        value(identifier, prefix: energyActionPrefix)
    }

    private static func value(_ identifier: String, prefix: String) -> Int? {
        guard identifier.hasPrefix(prefix), let value = Int(identifier.dropFirst(prefix.count)),
              (1...5).contains(value) else { return nil }
        return value
    }

    /// Today's check-in, opened with a mood already chosen.
    static func url(mood: Int) -> URL {
        URL(string: "khepri://check-ins?mood=\(mood)")!
    }

    /// The second banner: energy, for the mood just tapped.
    static func energyRequest(mood: Int, day: String, thread: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "And your energy?")
        content.categoryIdentifier = energyCategoryIdentifier
        content.threadIdentifier = thread
        content.userInfo = [moodKey: mood, dayKey: day]
        return UNNotificationRequest(identifier: "checkin-energy-\(day)", content: content, trigger: nil)
    }
}

/// What a button under a check-in banner does next.
enum CheckInNotificationFlow {
    enum Step: Equatable {
        case askEnergy(mood: Int, day: String)
        case file(mood: Int, energy: Int)
        case ignore
    }

    /// `today` is the local calendar day, as `CalendarDay` writes it.
    static func next(action: String, userInfo: [AnyHashable: Any], today: String) -> Step {
        if let mood = CheckInActions.mood(forAction: action) {
            return .askEnergy(mood: mood, day: today)
        }
        if let energy = CheckInActions.energy(forAction: action),
           let mood = userInfo[CheckInActions.moodKey] as? Int, (1...5).contains(mood),
           userInfo[CheckInActions.dayKey] as? String == today {
            return .file(mood: mood, energy: energy)
        }
        return .ignore
    }

    /// Files the check-in from the energy tap and says so in one last
    /// banner. If it cannot, the banner opens today's check-in with the mood
    /// set instead, so the two taps are not lost.
    static func file(mood: Int, energy: Int, thread: String) async {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = thread
        do {
            switch try await QuickCheckInFiler.live(source: "notification").file(mood: mood, energy: energy) {
            case let .filed(streak, momentTitle):
                content.title = streak > 1
                    ? String(localized: "Checked in · \(streak) days in a row")
                    : String(localized: "Checked in")
                if let momentTitle { content.body = momentTitle }
            case .alreadyCheckedIn:
                content.title = String(localized: "Already checked in today")
            }
            WidgetCenter.shared.reloadAllTimelines()
            await MainActor.run { NotificationCenter.default.post(name: .dayDataDidChange, object: nil) }
        } catch {
            content.title = String(localized: "Could not check in")
            content.body = String(localized: "Tap to finish it in Khepri.")
            content.userInfo = ["url": CheckInActions.url(mood: mood).absoluteString]
        }
        let request = UNNotificationRequest(identifier: "checkin-done", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
