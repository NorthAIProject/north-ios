import Foundation
import NorthAPI

/// A client for code that runs outside the app's own session handling:
/// widgets and the intents they share with the app.
///
/// It reads the mirrored token on every call and never signs anybody out. A
/// 401 here just fails the call; the app is the one that ends a session.
enum SharedAPI {
    enum Failure: LocalizedError {
        case signedOut

        var errorDescription: String? { "Open Khepri and sign in first." }
    }

    static var baseURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "NorthAPIBaseURL") as? String).flatMap(URL.init(string:))
    }

    /// Nil when nobody is signed in, so callers can show that instead of an
    /// error.
    static func client() -> Client? {
        guard let baseURL, SharedSession.token() != nil else { return nil }
        return NorthAPI.client(baseURL: baseURL, token: { SharedSession.token() })
    }

    static func requireClient() throws -> Client {
        guard let client = client() else { throw Failure.signedOut }
        return client
    }
}
