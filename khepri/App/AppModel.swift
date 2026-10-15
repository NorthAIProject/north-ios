import Foundation
import NorthAPI
import Observation
import UIKit

/// Where the app is in its life: which root screen to show.
///
/// One value decides the whole root view, so there is no combination of flags
/// that can show two roots at once or none.
enum AppPhase: Equatable {
    /// Restoring a stored session; nothing to show yet.
    case launching
    /// Launched before the first unlock after a restart: the session is in
    /// the Keychain but cannot be read until the phone is unlocked.
    case waitingForUnlock
    case signedOut
    /// Signed in, but the first-run questions are not answered.
    case onboarding(APIUser)
    case signedIn(APIUser)
    /// Signed in, but the account could not be loaded. `retry()` recovers.
    case failed(String)
}

/// The root state of the app: session, current user, and the phase derived
/// from them. Views read it from the environment and call its methods; they
/// never touch the session store directly.
@MainActor
@Observable
final class AppModel {
    private(set) var phase: AppPhase = .launching
    /// How the app is drawn: this iPhone's copy, replaced by the account's
    /// choice once the profile loads. `RootView` applies it to the windows.
    private(set) var appearance: AppearanceSetting
    @ObservationIgnored private var appearanceSave: Task<Void, Error>?
    static let appearancePendingKey = "appearance.pendingUpload"

    private let auth: AuthServicing
    private let sessions: AuthSessionManaging
    private let notifications: NotificationCenter
    private let settings: SettingsServicing
    private let defaults: UserDefaults
    /// Watching for the phone to unlock; present only while waiting for it.
    private var unlockObservers: [any NSObjectProtocol] = []
    private var restoring = false

    /// What may mean the Keychain can be read now: the phone was unlocked,
    /// or the app came forward (in case the unlock went unnoticed).
    static let unlockSignals: [Notification.Name] = [
        UIApplication.protectedDataDidBecomeAvailableNotification,
        UIApplication.didBecomeActiveNotification
    ]

    init(
        auth: AuthServicing = AuthService.shared,
        sessions: AuthSessionManaging = AuthSessionManager.shared,
        notifications: NotificationCenter = .default,
        settings: SettingsServicing? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.auth = auth
        self.sessions = sessions
        self.notifications = notifications
        self.settings = settings ?? SettingsService()
        self.defaults = defaults
        appearance = .stored(in: defaults)
    }

    /// Called once at launch: restores a stored session if there is one.
    func start() async {
        #if DEBUG
        // UI tests start from a clean install: no session, no saved wizard or
        // tour progress, no workout left to resume.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            await sessions.invalidateSession()
            WorkoutSnapshotStore().clear()
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
            appearance = .stored(in: defaults)
        }
        // Tests that are not about the tour mark it finished up front.
        if ProcessInfo.processInfo.arguments.contains("-uitest-skip-tour") {
            UserDefaults.standard.set(true, forKey: "guidedTour.finished")
        }
        #endif
        await restore()
    }

    /// The phone may have been unlocked: read the Keychain again. Does
    /// nothing unless the app is waiting for exactly that.
    func retryAfterUnlock() async {
        guard phase == .waitingForUnlock, !restoring else { return }
        restoring = true
        defer { restoring = false }
        await restore()
    }

    /// A sign-in screen finished; the session is already stored.
    func didSignIn() async {
        await loadUser()
        // The APNs token usually arrived before anybody was signed in.
        await PushRegistration.resend()
        await PushRegistration.registerIfAllowed()
        // An invite link tapped before signing in.
        await PendingInvite.redeemIfAny()
        _ = await PendingCrewJoin.joinIfAny()
    }

    /// The first-run wizard finished and the server accepted the answers.
    func didCompleteOnboarding(_ user: APIUser) {
        phase = .signedIn(user)
        Task {
            await PendingInvite.redeemIfAny()
            _ = await PendingCrewJoin.joinIfAny()
        }
    }

    func retry() async {
        await loadUser()
    }

    /// Draws the app this way at once and keeps it on this iPhone.
    func chooseAppearance(_ choice: AppearanceSetting) {
        adopt(choice)
    }

    /// Saves the current appearance to the account. Signed out there is no
    /// account and nothing is sent. A failure leaves this iPhone's copy in
    /// place, marked to be sent at the next sync, and is thrown for the
    /// caller to show.
    ///
    /// Saves run one after another and each sends the choice current when it
    /// runs, so picking Dark then Light quickly cannot leave Dark on the
    /// account. A save overtaken by a later one reports nothing.
    func saveAppearanceToAccount() async throws {
        switch phase {
        case .signedIn, .onboarding:
            break
        case .launching, .waitingForUnlock, .signedOut, .failed:
            return
        }
        let previous = appearanceSave
        let save = Task { [settings] in
            _ = try? await previous?.value
            try await settings.saveAppearance(self.appearance)
        }
        appearanceSave = save
        do {
            try await save.value
        } catch {
            guard save == appearanceSave else { return }
            defaults.set(true, forKey: Self.appearancePendingKey)
            throw error
        }
        if save == appearanceSave {
            defaults.removeObject(forKey: Self.appearancePendingKey)
        }
    }

    func signOut() async {
        // While the session can still authenticate the call.
        await PushRegistration.unregister()
        await auth.logout()
        await SpotlightIndex.clear()
        // A workout in progress belongs to this account, not the next one.
        WorkoutSnapshotStore().clear()
        phase = .signedOut
    }

    /// The session was rejected or cleared somewhere else, e.g. a 401.
    /// A workout in progress is kept: signing back in resumes it.
    func sessionEnded() {
        phase = .signedOut
        Task { await SpotlightIndex.clear() }
    }

    private func restore() async {
        switch await sessions.restoreSessionIfNeeded() {
        case .restored:
            stopWaitingForUnlock()
            phase = .launching
            await loadUser()
        case .none:
            stopWaitingForUnlock()
            phase = .signedOut
        case .locked:
            // Never sign out here: the session is intact, only unreadable.
            waitForUnlock()
        }
    }

    private func waitForUnlock() {
        phase = .waitingForUnlock
        guard unlockObservers.isEmpty else { return }
        unlockObservers = Self.unlockSignals.map { name in
            notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.retryAfterUnlock() }
            }
        }
    }

    private func stopWaitingForUnlock() {
        unlockObservers.forEach(notifications.removeObserver)
        unlockObservers = []
    }

    /// The account's language and appearance may have changed on the web.
    /// The language shows from the next launch, the appearance at once. Best
    /// effort: an offline launch keeps this iPhone's copies.
    func syncFromAccount() async {
        let before = appearance
        guard let profile = try? await settings.profile() else { return }
        AppLanguage.apply(profile.locale, defaults: defaults)
        // A choice that never reached the account is sent now rather than
        // replaced by the account's older one.
        if defaults.bool(forKey: Self.appearancePendingKey) {
            try? await saveAppearanceToAccount()
            return
        }
        // An account that never chose keeps this iPhone's choice, and so does
        // a choice made here while the profile was loading.
        if let value = profile.appearance, appearance == before {
            adopt(AppearanceSetting(profileValue: value))
        }
    }

    private func adopt(_ choice: AppearanceSetting) {
        appearance = choice
        choice.store(in: defaults)
    }

    private func loadUser() async {
        do {
            let user = try await auth.currentUser()
            AppTimeZone.current = TimeZone(identifier: user.timezone) ?? .current
            phase = user.needsOnboarding ? .onboarding(user) : .signedIn(user)
            Task { await syncFromAccount() }
        } catch let error as APIError where error.isUnauthorized {
            await sessions.invalidateSession()
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
