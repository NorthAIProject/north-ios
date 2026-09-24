import AuthenticationServices
import CryptoKit
import Foundation
import NorthAPI
import UIKit

public struct AppleAuthCredentialResult: Sendable {
    public let identityToken: String
    public let authorizationCode: String
    public let rawNonce: String
    public let fullName: String?
    public let email: String?

    public init(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String,
        fullName: String? = nil,
        email: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.rawNonce = rawNonce
        self.fullName = fullName
        self.email = email
    }
}

public protocol AppleSignInCoordinating: AnyObject, Sendable {
    @MainActor
    func signIn() async throws -> AppleAuthCredentialResult
}

public final class AppleSignInCoordinator: NSObject, AppleSignInCoordinating, @unchecked Sendable {
    @MainActor
    public func signIn() async throws -> AppleAuthCredentialResult {
        let handler = AppleSignInSessionHandler()
        return try await withCheckedThrowingContinuation { continuation in
            handler.start(continuation: continuation)
        }
    }
}

@MainActor
private final class AppleSignInSessionHandler: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleAuthCredentialResult, Error>?
    private var currentNonce: String?

    func start(continuation: CheckedContinuation<AppleAuthCredentialResult, Error>) {
        self.continuation = continuation
        let nonce = randomNonceString()
        self.currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }

    // MARK: - ASAuthorizationControllerDelegate

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: APIError.server("Invalid Apple authorization credential."))
                continuation = nil
                return
            }

            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                continuation?.resume(throwing: APIError.server("Apple identity token was missing or malformed."))
                continuation = nil
                return
            }

            guard let authCodeData = appleIDCredential.authorizationCode,
                  let authorizationCode = String(data: authCodeData, encoding: .utf8) else {
                continuation?.resume(throwing: APIError.server("Apple authorization code was missing."))
                continuation = nil
                return
            }

            var fullName: String?
            if let personName = appleIDCredential.fullName {
                let formatter = PersonNameComponentsFormatter()
                let formatted = formatter.string(from: personName).trimmingCharacters(in: .whitespacesAndNewlines)
                if !formatted.isEmpty {
                    fullName = formatted
                }
            }

            let result = AppleAuthCredentialResult(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: currentNonce ?? "",
                fullName: fullName,
                email: appleIDCredential.email
            )

            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                continuation?.resume(throwing: OAuthWebAuthenticationError.cancelled)
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    // MARK: - Presentation Context

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }

    // MARK: - Crypto Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
