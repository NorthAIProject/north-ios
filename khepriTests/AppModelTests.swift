import Foundation
import Testing
import UIKit
@testable import khepri

/// Launching before the first unlock after a restart: the Keychain will not
/// hand over the session yet, and that must not look like being signed out.
@MainActor
struct AppModelUnlockTests {
    @Test func aLockedKeychainWaitsForUnlockAndKeepsTheSession() async throws {
        let (model, store, _) = try await lockedLaunch()

        await model.start()

        #expect(model.phase == .waitingForUnlock)
        #expect(store.storage["auth_session_token"] == "kept")
    }

    @Test func protectedDataBecomingAvailableRestoresTheSession() async throws {
        let (model, store, center) = try await lockedLaunch()
        await model.start()

        store.locked = false
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        try await until { model.phase == .onboarding(.fixture) }
    }

    /// Coming to the foreground retries too, in case the unlock was missed.
    /// While still locked it keeps waiting.
    @Test func becomingActiveRetriesAndKeepsWaitingWhileLocked() async throws {
        let (model, store, center) = try await lockedLaunch()
        await model.start()

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .waitingForUnlock)

        store.locked = false
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        try await until { model.phase == .onboarding(.fixture) }
        #expect(store.storage["auth_session_token"] == "kept")
    }

    @Test func noSessionIsSignedOut() async {
        let model = AppModel(
            auth: FakeAuth(),
            sessions: AuthSessionManager(secureStore: MemoryStore()),
            notifications: NotificationCenter()
        )

        await model.start()

        #expect(model.phase == .signedOut)
    }

    private func lockedLaunch() async throws -> (AppModel, MemoryStore, NotificationCenter) {
        let store = MemoryStore()
        let sessions = AuthSessionManager(secureStore: store)
        try await sessions.storeSession(token: "kept", user: nil, expiresAt: nil)
        store.locked = true
        let center = NotificationCenter()
        return (AppModel(auth: FakeAuth(), sessions: sessions, notifications: center), store, center)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
