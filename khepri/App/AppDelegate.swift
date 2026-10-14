import os
import UIKit
import UserNotifications

/// What only a UIKit app delegate can do: receive notification taps, decide
/// how notifications appear while the app is open, and be woken for
/// background uploads.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Links from notification taps, handed to the router once it exists.
    @MainActor var onOpenURL: ((URL) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([WorkoutReminders.category, CheckInActions.category])
        // Before launch finishes, or HealthKit drops background deliveries.
        HealthBackgroundDelivery.register()
        // A workout Live Activity from before a kill has nothing behind it
        // now, unless that workout is about to be resumed.
        WorkoutLiveActivityController.endOrphans()
        Task { @MainActor in await PushRegistration.registerIfAllowed() }
        // Reconnects to form-check uploads from before a kill or relaunch.
        Task { @MainActor in await FormCheckUploader.shared.reconcile() }
        return true
    }

    /// iOS woke the app to deliver what happened to background uploads.
    /// Using the uploader recreates its session with the same identifier,
    /// which is what lets the events arrive; the handler is called once they
    /// all have.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploadSession.identifier else {
            completionHandler()
            return
        }
        FormCheckUploader.shared.backgroundEventsCompletion = completionHandler
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PushRegistration.didReceive(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Logger(subsystem: "com.fernandocorreia.khepri", category: "push")
            .error("push: registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Shown even when the app is open: a reminder is still useful then.
    /// The end of a rest is not: the workout on screen says it with a haptic.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == RestNotifications.identifier ? [] : [.banner, .sound]
    }

    /// A tap, or the Start Workout button, opens where the notification says.
    /// A mood button on a check-in nudge opens today's check-in with that mood
    /// instead. The nudge is still opened first, so the server counts the tap.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // A nudge from the server carries the web's link in `href`.
        if let href = response.notification.request.content.userInfo["href"] as? String {
            let checkIn = CheckInActions.mood(forAction: response.actionIdentifier).map(CheckInActions.url(mood:))
            await MainActor.run { [href, checkIn] in
                Task { @MainActor in await PushRegistration.open(href: href) { self.onOpenURL?(checkIn ?? $0) } }
            }
            return
        }
        guard let link = response.notification.request.content.userInfo["url"] as? String, var url = URL(string: link) else { return }
        if response.actionIdentifier == WorkoutReminders.startActionIdentifier {
            url.append(component: "start")
        }
        await MainActor.run { [url] in onOpenURL?(url) }
    }
}
