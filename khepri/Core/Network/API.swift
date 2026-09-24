import Foundation
import NorthAPI

/// The one generated client the app talks to the server through.
///
/// Built once, from the build's base URL and the signed-in session. A 401 on
/// any authenticated call ends the session, which sends the app back to sign
/// in wherever the call was made from.
enum API {
    static let shared: Client = NorthAPI.client(
        baseURL: AppEnvironment.apiBaseURL,
        token: { try? await AuthSessionManager.shared.validAccessToken() },
        onUnauthorized: { await AuthSessionManager.shared.invalidateSession() }
    )
}
