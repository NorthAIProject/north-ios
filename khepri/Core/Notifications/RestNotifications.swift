import Foundation
import os
import UserNotifications

/// The end of a rest, for the notification that says so.
nonisolated struct RestEnd: Equatable, Sendable {
    let endsAt: Date
    /// The set waiting after the rest.
    let exerciseName: String
    let setNumber: Int
    let totalSets: Int
}

/// Says "rest over" when the phone is in a pocket. A protocol so the
/// workout's tests can see what it would have scheduled.
@MainActor
protocol RestNotificationScheduling: AnyObject {
    /// Schedules the rest-end notification, replacing any earlier one.
    func schedule(_ rest: RestEnd)
    /// Takes back the rest-end notification, pending or already shown.
    func cancel()
}

/// One local notification, always under the same identifier, so scheduling
/// again replaces it and cancelling needs no bookkeeping.
///
/// It only schedules when notifications are already allowed: a workout is
/// the wrong moment for the permission prompt, which onboarding and
/// Settings ask for. While the app is open the notification is not shown
/// (see `AppDelegate`): the haptic at the end of rest already says it.
@MainActor
final class RestNotifications: RestNotificationScheduling {
    nonisolated static let identifier = "workout.rest-end"

    private let center: UNUserNotificationCenter
    /// The rest end the system should be holding; nil after a cancel. A
    /// schedule still waiting on the settings check gives way to whatever
    /// came after it.
    private var wanted: RestEnd?
    private let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "rest-notification")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func schedule(_ rest: RestEnd) {
        wanted = rest
        Task {
            let status = await center.notificationSettings().authorizationStatus
            guard wanted == rest, Self.allowsAlerts(status) else { return }
            let interval = rest.endsAt.timeIntervalSinceNow
            guard interval >= 1 else { return }
            do {
                try await center.add(Self.request(for: rest, firingIn: interval))
            } catch {
                log.error("rest notification not scheduled: \(error.localizedDescription, privacy: .public)")
            }
            // Cancelled while it was being added.
            if wanted == nil { center.removePendingNotificationRequests(withIdentifiers: [Self.identifier]) }
        }
    }

    func cancel() {
        wanted = nil
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    nonisolated static func allowsAlerts(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    /// The default interruption level: time-sensitive needs an entitlement
    /// this app does not have.
    nonisolated static func request(for rest: RestEnd, firingIn interval: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest over")
        content.body = String(localized: "Next set: \(rest.exerciseName), set \(rest.setNumber) of \(rest.totalSets).")
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
