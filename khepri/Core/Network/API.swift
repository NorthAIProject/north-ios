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

    /// For requests that wait on a whole model generation before the server
    /// sends a byte, such as a new training plan (one to three minutes).
    /// URLSession's default 60 s idle timeout would give up first; every
    /// other call keeps it, so a dead connection still fails fast.
    static let generation: Client = NorthAPI.client(
        baseURL: AppEnvironment.apiBaseURL,
        token: { try? await AuthSessionManager.shared.validAccessToken() },
        onUnauthorized: { await AuthSessionManager.shared.invalidateSession() },
        session: URLSession(configuration: {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 300
            return configuration
        }())
    )
}
