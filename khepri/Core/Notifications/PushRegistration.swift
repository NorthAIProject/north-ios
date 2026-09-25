import NorthAPI
import os
import UIKit
import UserNotifications

/// Hands the server this install's APNs token, so nudges reach the Lock Screen.
///
/// iOS often delivers the token before anybody has signed in, so the latest
/// one is kept and sent again after sign-in. Sign-out forgets it on the server
/// while the session can still authenticate the call.
@MainActor
enum PushRegistration {
    private static let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "push")
    private static let tokenKey = "push.apnsToken"

    /// Xcode builds get sandbox tokens; TestFlight and the App Store get
    /// production ones. Sending a token to the wrong host fails as a bad token.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks iOS for a token when notifications are allowed. Asking for
    /// permission is the wizard's job; this never prompts.
    static func registerIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            log.info("push: notifications not allowed, not registering")
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func didReceive(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        await send(token)
    }

    /// Sends the stored token again: after sign-in, and on each launch in case
    /// the server forgot it.
    static func resend() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        await send(token)
    }

    private static func send(_ token: String) async {
        guard await AuthSessionManager.shared.restoreSessionIfNeeded() else {
            log.info("push: token held until sign-in")
            return
        }
        let body = Components.Schemas.APNsDeviceInput(
            token: token,
            topic: Bundle.main.bundleIdentifier ?? "",
            environment: environment == "sandbox" ? .sandbox : .production
        )
        do {
            try await NorthAPI.call { _ = try await API.shared.registerAPNsDevice(body: .json(body)).noContent }
            log.info("push: registered with the server (\(environment, privacy: .public))")
        } catch {
            // 503 means the server has no APNs key yet; nothing to do.
            log.error("push: could not register: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forgets this install on the server. Called just before sign-out.
    static func unregister() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        do {
            try await NorthAPI.call { _ = try await API.shared.unregisterAPNsDevice(path: .init(token: token)).noContent }
        } catch {
            log.error("push: could not unregister: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A tapped nudge: marks it opened from push, then goes where it leads.
    /// The payload's `href` is the web's `/app/nudges/<id>/open?from=push`.
    static func open(href: String, router: (URL) -> Void) async {
        let parts = URL(string: href)?.pathComponents ?? []
        guard let index = parts.firstIndex(of: "nudges"), parts.indices.contains(index + 1) else {
            if let url = URL(string: href) { router(url) }
            return
        }
        do {
            let nudge = try await NorthAPI.call {
                try await API.shared.openNudge(path: .init(nudgeID: parts[index + 1]), query: .init(from: .push)).ok.body.json
            }
            if let url = URL(string: nudge.href) { router(url) }
        } catch {
            log.error("push: could not open nudge: \(error.localizedDescription, privacy: .public)")
            router(URL(string: "khepri://today")!)
        }
    }
}
