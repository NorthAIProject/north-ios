import AuthenticationServices
import Foundation
import UIKit

public enum OAuthWebAuthenticationError: LocalizedError, Sendable {
    case unableToStart
    case cancelled
    case invalidCallback
    case missingCode
    case missingState
    case invalidAuthorizationURL

    public var errorDescription: String? {
        switch self {
        case .unableToStart: return "Could not start OAuth sign in."
        case .cancelled: return "OAuth sign in was cancelled."
        case .invalidCallback: return "OAuth callback was invalid."
        case .missingCode: return "OAuth callback did not return an authorization code."
        case .missingState: return "OAuth callback did not return state."
        case .invalidAuthorizationURL: return "OAuth authorization URL is invalid."
        }
    }
}

public protocol OAuthWebAuthenticating: AnyObject, Sendable {
    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

public final class OAuthWebAuthenticator: NSObject, OAuthWebAuthenticating, @unchecked Sendable {
    @MainActor
    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let coordinator = OAuthWebAuthenticationCoordinator()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.start(url: url, callbackScheme: callbackScheme, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in coordinator.cancel() }
        }
    }
}

@MainActor
private final class OAuthWebAuthenticationCoordinator {
    private var session: ASWebAuthenticationSession?
    private var contextProvider: OAuthPresentationContextProvider?
    private var continuation: CheckedContinuation<URL, Error>?

    func start(url: URL, callbackScheme: String, continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor in self?.finish(callbackURL: callbackURL, error: error) }
        }
        let contextProvider = OAuthPresentationContextProvider()
        self.contextProvider = contextProvider
        session.presentationContextProvider = contextProvider
        session.prefersEphemeralWebBrowserSession = true
        self.session = session

        guard session.start() else {
            resume(throwing: OAuthWebAuthenticationError.unableToStart)
            return
        }
    }

    func cancel() {
        session?.cancel()
        resume(throwing: OAuthWebAuthenticationError.cancelled)
    }

    private func finish(callbackURL: URL?, error: Error?) {
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            resume(throwing: OAuthWebAuthenticationError.cancelled)
            return
        }
        if let error {
            resume(throwing: error)
            return
        }
        guard let callbackURL else {
            resume(throwing: OAuthWebAuthenticationError.invalidCallback)
            return
        }
        resume(returning: callbackURL)
    }

    private func resume(returning callbackURL: URL) {
        guard let continuation else { return }
        clearState()
        continuation.resume(returning: callbackURL)
    }

    private func resume(throwing error: Error) {
        guard let continuation else { return }
        clearState()
        continuation.resume(throwing: error)
    }

    private func clearState() {
        continuation = nil
        session = nil
        contextProvider = nil
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
