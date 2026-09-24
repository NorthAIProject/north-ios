import Foundation

public extension Notification.Name {
    static let authSessionDidAuthenticate = Notification.Name("khepri.authSessionDidAuthenticate")
    static let authSessionWillInvalidate = Notification.Name("khepri.authSessionWillInvalidate")
    static let authSessionDidInvalidate = Notification.Name("khepri.authSessionDidInvalidate")
}

public protocol AuthSessionManaging: Sendable {
    func restoreSessionIfNeeded() async -> Bool
    func validAccessToken() async throws -> String?
    func storeSession(token: String, user: UserDTO?, expiresAt: Date?) async throws
    func logout() async
    func invalidateSession() async
}

public final class AuthSessionManager: AuthSessionManaging, @unchecked Sendable {
    public static let shared = AuthSessionManager()

    private let secureStore: SecureStringStoring
    private let tokenKey = "auth_session_token"
    private let userKey = "auth_session_user"
    private let expiresAtKey = "auth_session_expires_at"

    public init(secureStore: SecureStringStoring = KeychainStringStore()) {
        self.secureStore = secureStore
    }

    public func restoreSessionIfNeeded() async -> Bool {
        do {
            let token = try await validAccessToken()
            return !(token?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    public func validAccessToken() async throws -> String? {
        guard let token = try secureStore.string(for: tokenKey), !token.isEmpty else {
            return nil
        }

        // Session tokens are opaque; the server sends their expiry alongside.
        if let raw = try? secureStore.string(for: expiresAtKey),
           let expiry = try? Date(raw, strategy: .iso8601),
           expiry <= Date() {
            await invalidateSession()
            return nil
        }

        return token
    }

    public func storeSession(token: String, user: UserDTO?, expiresAt: Date?) async throws {
        try secureStore.setString(token, for: tokenKey)
        if let expiresAt {
            try? secureStore.setString(expiresAt.formatted(.iso8601), for: expiresAtKey)
        } else {
            try? secureStore.removeValue(for: expiresAtKey)
        }
        if let user, let userData = try? JSONEncoder().encode(user), let userJson = String(data: userData, encoding: .utf8) {
            try? secureStore.setString(userJson, for: userKey)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .authSessionDidAuthenticate, object: nil)
        }
    }

    public func logout() async {
        await invalidateSession()
    }

    public func invalidateSession() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .authSessionWillInvalidate, object: nil)
        }

        try? secureStore.removeValue(for: tokenKey)
        try? secureStore.removeValue(for: userKey)
        try? secureStore.removeValue(for: expiresAtKey)

        await MainActor.run {
            NotificationCenter.default.post(name: .authSessionDidInvalidate, object: nil)
        }
    }
}
