import os
import UIKit
import UserNotifications

/// What only a UIKit app delegate can do: receive notification taps, decide
/// how notifications appear while the app is open, and be woken for
/// background uploads.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Links from notification taps, handed to the router once it exists.
    @MainActor var onOpenURL: ((URL) -> Void)?
    /// A crew push arrived while the app is open: the unread badges refresh.
    @MainActor var onCrewPush: (() -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let categories = [WorkoutReminders.category, CheckInActions.category, CrewNotifications.notificationCategory]
        center.setNotificationCategories(Set(categories + CoachActions.categories))
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
    /// Nor is a crew message in the channel on screen, which shows it already.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier == RestNotifications.identifier { return [] }
        let content = notification.request.content
        if content.categoryIdentifier == CrewNotifications.category {
            let href = content.userInfo["href"] as? String
            let open = await MainActor.run {
                onCrewPush?()
                return CrewNotifications.openChannel
            }
            if !CrewNotifications.shouldPresent(href: href, open: open) { return [] }
        }
        return [.banner, .sound]
    }

    /// A tap, or the Start Workout button, opens where the notification says.
    /// A mood button on a check-in nudge opens today's check-in with that mood
    /// instead. The nudge is still opened first, so the server counts the tap.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // A button under the coach's message answers it where it stands,
        // without opening the app.
        if let answer = CoachActions.answer(forAction: response.actionIdentifier) {
            _ = try? await OutreachService().answer(id: "today", action: answer)
            return
        }
        // Text typed under a crew message goes to its channel, also without
        // opening the app.
        if response.actionIdentifier == CrewNotifications.replyAction {
            let request = response.notification.request
            guard let text = (response as? UNTextInputNotificationResponse)?.userText,
                  let href = request.content.userInfo["href"] as? String else { return }
            await CrewNotifications.reply(text, href: href, notificationID: request.identifier)
            return
        }
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
