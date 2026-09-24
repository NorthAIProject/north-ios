import AuthenticationServices
import Foundation
import NorthAPI
import UIKit

public struct PasskeyAssertionResult: Sendable {
    public let credentialID: String
    public let rawID: String
    public let clientDataJSON: String
    public let authenticatorData: String
    public let signature: String
    public let userHandle: String?

    public init(
        credentialID: String,
        rawID: String,
        clientDataJSON: String,
        authenticatorData: String,
        signature: String,
        userHandle: String? = nil
    ) {
        self.credentialID = credentialID
        self.rawID = rawID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }

    /// The assertion as WebAuthn PublicKeyCredential JSON, the shape the
    /// server's ceremony parses. Binary fields are already base64url.
    public var credentialJSON: [String: Any] {
        var response: [String: Any] = [
            "clientDataJSON": clientDataJSON,
            "authenticatorData": authenticatorData,
            "signature": signature,
        ]
        if let userHandle {
            response["userHandle"] = userHandle
        }
        return [
            "id": credentialID,
            "rawId": rawID,
            "type": "public-key",
            "response": response,
            "clientExtensionResults": [String: Any](),
        ]
    }
}

public struct PasskeyRegistrationResult: Sendable {
    public let credentialID: String
    public let rawID: String
    public let clientDataJSON: String
    public let attestationObject: String

    public init(
        credentialID: String,
        rawID: String,
        clientDataJSON: String,
        attestationObject: String
    ) {
        self.credentialID = credentialID
        self.rawID = rawID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }

    /// The attestation as WebAuthn PublicKeyCredential JSON.
    public var credentialJSON: [String: Any] {
        [
            "id": credentialID,
            "rawId": rawID,
            "type": "public-key",
            "response": [
                "clientDataJSON": clientDataJSON,
                "attestationObject": attestationObject,
            ],
            "clientExtensionResults": [String: Any](),
        ]
    }
}

public protocol PasskeyCoordinating: AnyObject, Sendable {
    @MainActor
    func loginWithPasskey(relyingPartyID: String, challenge: Data) async throws -> PasskeyAssertionResult

    @MainActor
    func registerPasskey(relyingPartyID: String, challenge: Data, userName: String, userID: Data) async throws -> PasskeyRegistrationResult
}

public final class PasskeyCoordinator: NSObject, PasskeyCoordinating, @unchecked Sendable {
    @MainActor
    public func loginWithPasskey(relyingPartyID: String, challenge: Data) async throws -> PasskeyAssertionResult {
        let session = PasskeySessionHandler()
        return try await withCheckedThrowingContinuation { continuation in
            session.startAssertion(relyingPartyID: relyingPartyID, challenge: challenge, continuation: continuation)
        }
    }

    @MainActor
    public func registerPasskey(relyingPartyID: String, challenge: Data, userName: String, userID: Data) async throws -> PasskeyRegistrationResult {
        let session = PasskeySessionHandler()
        return try await withCheckedThrowingContinuation { continuation in
            session.startRegistration(relyingPartyID: relyingPartyID, challenge: challenge, userName: userName, userID: userID, continuation: continuation)
        }
    }
}

@MainActor
private final class PasskeySessionHandler: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var assertionContinuation: CheckedContinuation<PasskeyAssertionResult, Error>?
    private var registrationContinuation: CheckedContinuation<PasskeyRegistrationResult, Error>?

    func startAssertion(relyingPartyID: String, challenge: Data, continuation: CheckedContinuation<PasskeyAssertionResult, Error>) {
        self.assertionContinuation = continuation
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyID)
        let request = platformProvider.createCredentialAssertionRequest(challenge: challenge)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func startRegistration(relyingPartyID: String, challenge: Data, userName: String, userID: Data, continuation: CheckedContinuation<PasskeyRegistrationResult, Error>) {
        self.registrationContinuation = continuation
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyID)
        let request = platformProvider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - ASAuthorizationControllerDelegate

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                let result = PasskeyAssertionResult(
                    credentialID: credential.credentialID.base64URLEncoded(),
                    rawID: credential.credentialID.base64URLEncoded(),
                    clientDataJSON: credential.rawClientDataJSON.base64URLEncoded(),
                    authenticatorData: credential.rawAuthenticatorData.base64URLEncoded(),
                    signature: credential.signature.base64URLEncoded(),
                    userHandle: credential.userID.map { $0.base64URLEncoded() }
                )
                assertionContinuation?.resume(returning: result)
                assertionContinuation = nil
            } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                guard let attestationObject = credential.rawAttestationObject else {
                    registrationContinuation?.resume(throwing: APIError.server("Missing attestation object from passkey registration."))
                    registrationContinuation = nil
                    return
                }

                let result = PasskeyRegistrationResult(
                    credentialID: credential.credentialID.base64URLEncoded(),
                    rawID: credential.credentialID.base64URLEncoded(),
                    clientDataJSON: credential.rawClientDataJSON.base64URLEncoded(),
                    attestationObject: attestationObject.base64URLEncoded()
                )
                registrationContinuation?.resume(returning: result)
                registrationContinuation = nil
            } else {
                let error = APIError.server("Unsupported credential type returned.")
                assertionContinuation?.resume(throwing: error)
                registrationContinuation?.resume(throwing: error)
                assertionContinuation = nil
                registrationContinuation = nil
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                assertionContinuation?.resume(throwing: OAuthWebAuthenticationError.cancelled)
                registrationContinuation?.resume(throwing: OAuthWebAuthenticationError.cancelled)
            } else {
                assertionContinuation?.resume(throwing: error)
                registrationContinuation?.resume(throwing: error)
            }
            assertionContinuation = nil
            registrationContinuation = nil
        }
    }

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
}

public extension Data {
    func base64URLEncoded() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
