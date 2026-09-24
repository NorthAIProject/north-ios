import UIKit
import UserNotifications

/// What only a UIKit app delegate can do: receive notification taps and
/// decide how notifications appear while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Links from notification taps, handed to the router once it exists.
    @MainActor var onOpenURL: ((URL) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([WorkoutReminders.category])
        return true
    }

    /// Shown even when the app is open: a reminder is still useful then.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// A tap, or the Start Workout button, opens where the notification says.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String, var url = URL(string: link) else { return }
        if response.actionIdentifier == WorkoutReminders.startActionIdentifier {
            url.append(component: "start")
        }
        await MainActor.run { [url] in onOpenURL?(url) }
    }
}
