import Foundation
import NorthAPI
import Observation

/// Where the app is in its life: which root screen to show.
///
/// One value decides the whole root view, so there is no combination of flags
/// that can show two roots at once or none.
enum AppPhase: Equatable {
    /// Restoring a stored session; nothing to show yet.
    case launching
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

    private let auth: AuthServicing
    private let sessions: AuthSessionManaging

    init(auth: AuthServicing = AuthService.shared, sessions: AuthSessionManaging = AuthSessionManager.shared) {
        self.auth = auth
        self.sessions = sessions
    }

    /// Called once at launch: restores a stored session if there is one.
    func start() async {
        #if DEBUG
        // UI tests start from a clean install: no session, no saved wizard or
        // tour progress.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            await sessions.invalidateSession()
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
        }
        // Tests that are not about the tour mark it finished up front.
        if ProcessInfo.processInfo.arguments.contains("-uitest-skip-tour") {
            UserDefaults.standard.set(true, forKey: "guidedTour.finished")
        }
        #endif
        if await sessions.restoreSessionIfNeeded() {
            await loadUser()
        } else {
            phase = .signedOut
        }
    }

    /// A sign-in screen finished; the session is already stored.
    func didSignIn() async {
        await loadUser()
    }

    /// The first-run wizard finished and the server accepted the answers.
    func didCompleteOnboarding(_ user: APIUser) {
        phase = .signedIn(user)
    }

    func retry() async {
        await loadUser()
    }

    func signOut() async {
        await auth.logout()
        phase = .signedOut
    }

    /// The session was rejected or cleared somewhere else, e.g. a 401.
    func sessionEnded() {
        phase = .signedOut
    }

    private func loadUser() async {
        do {
            let user = try await auth.currentUser()
            AppTimeZone.current = TimeZone(identifier: user.timezone) ?? .current
            phase = user.needsOnboarding ? .onboarding(user) : .signedIn(user)
        } catch let error as APIError where error.isUnauthorized {
            await sessions.invalidateSession()
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
