import Foundation
import GoogleSignIn
import NorthAPI
import UIKit

public protocol AuthServicing: Sendable {
    func currentUser() async throws -> APIUser
    func today() async throws -> TodayResponse
    func completeOnboarding(_ answers: OnboardingAnswers) async throws -> APIUser
    func login(email: String, password: String) async throws -> AuthSession
    func signup(email: String, password: String, passwordConfirmation: String, displayName: String) async throws -> AuthSession
    func forgotPassword(email: String) async throws
    @MainActor
    func signInWithGoogle() async throws -> AuthSession
    @MainActor
    func signInWithApple() async throws -> AuthSession
    @MainActor
    func signInWithPasskey() async throws -> AuthSession
    @MainActor
    func registerPasskey(email: String, displayName: String) async throws -> AuthSession
    func logout() async
}

/// Signs in and out, and reads the signed-in user's first screens, through the
/// client generated from the server's OpenAPI contract.
public final class AuthService: AuthServicing, @unchecked Sendable {
    public static let shared = AuthService()

    private let api: Client
    private let sessionManager: AuthSessionManaging
    private let appleCoordinator: AppleSignInCoordinating
    private let passkeyCoordinator: PasskeyCoordinating
    private let baseURL: URL

    public init(
        baseURL: URL = AppEnvironment.apiBaseURL,
        api: Client? = nil,
        sessionManager: AuthSessionManaging = AuthSessionManager.shared,
        appleCoordinator: AppleSignInCoordinating = AppleSignInCoordinator(),
        passkeyCoordinator: PasskeyCoordinating = PasskeyCoordinator()
    ) {
        self.baseURL = baseURL
        self.sessionManager = sessionManager
        self.api = api ?? API.shared
        self.appleCoordinator = appleCoordinator
        self.passkeyCoordinator = passkeyCoordinator
    }

    // MARK: Signed-in reads

    public func currentUser() async throws -> APIUser {
        try await NorthAPI.call { try await api.getMe().ok.body.json.user }
    }

    public func today() async throws -> TodayResponse {
        try await NorthAPI.call { try await api.getToday().ok.body.json }
    }

    public func completeOnboarding(_ answers: OnboardingAnswers) async throws -> APIUser {
        try await NorthAPI.call { try await api.completeOnboarding(body: .json(answers)).ok.body.json.user }
    }

    // MARK: Email and password

    public func login(email: String, password: String) async throws -> AuthSession {
        let session = try await NorthAPI.call {
            try await api.logIn(body: .json(.init(email: email, password: password))).ok.body.json
        }
        return try await store(session)
    }

    public func signup(email: String, password: String, passwordConfirmation: String, displayName: String) async throws -> AuthSession {
        let request = Components.Schemas.SignupRequest(
            email: email,
            password: password,
            passwordConfirmation: passwordConfirmation,
            displayName: displayName,
            timezone: TimeZone.current.identifier
        )
        let session = try await NorthAPI.call { try await api.signUp(body: .json(request)).created.body.json }
        return try await store(session)
    }

    public func forgotPassword(email: String) async throws {
        _ = try await NorthAPI.call { try await api.requestPasswordReset(body: .json(.init(email: email))).accepted }
    }

    // MARK: Google and Apple

    @MainActor
    public func signInWithGoogle() async throws -> AuthSession {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty else {
            throw APIError.server("Google sign-in is not configured for this build.")
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = Self.presentingViewController() else {
            throw OAuthWebAuthenticationError.unableToStart
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw OAuthWebAuthenticationError.missingCode
        }
        let session = try await NorthAPI.call {
            try await api.signInWithGoogle(body: .json(.init(idToken: idToken))).ok.body.json
        }
        return try await store(session)
    }

    @MainActor
    public func signInWithApple() async throws -> AuthSession {
        let result = try await appleCoordinator.signIn()
        let request = Components.Schemas.AppleRequest(
            identityToken: result.identityToken,
            authorizationCode: result.authorizationCode,
            nonce: result.rawNonce,
            fullName: result.fullName,
            email: result.email
        )
        let session = try await NorthAPI.call { try await api.signInWithApple(body: .json(request)).ok.body.json }
        return try await store(session)
    }

    // MARK: Passkeys

    @MainActor
    public func signInWithPasskey() async throws -> AuthSession {
        let ceremony = try await NorthAPI.call { try await api.beginPasskeyLogin().ok.body.json }
        let options = ceremony.publicKey.additionalProperties.json
        let challenge = try Self.challenge(in: options)
        let rpID = options["rpId"] as? String ?? baseURL.host ?? "localhost"

        let assertion = try await passkeyCoordinator.loginWithPasskey(relyingPartyID: rpID, challenge: challenge)

        let finish = try Components.Schemas.PasskeyFinishRequest(
            challengeId: ceremony.challengeId,
            credential: .init(additionalProperties: .init(json: assertion.credentialJSON))
        )
        let session = try await NorthAPI.call { try await api.finishPasskeyLogin(body: .json(finish)).ok.body.json }
        return try await store(session)
    }

    @MainActor
    public func registerPasskey(email: String, displayName: String) async throws -> AuthSession {
        let begin = Components.Schemas.PasskeyRegisterBeginRequest(
            email: email,
            displayName: displayName,
            timezone: TimeZone.current.identifier
        )
        let ceremony = try await NorthAPI.call { try await api.beginPasskeyRegistration(body: .json(begin)).ok.body.json }
        let options = ceremony.publicKey.additionalProperties.json
        let challenge = try Self.challenge(in: options)
        let rpID = (options["rp"] as? [String: Any])?["id"] as? String ?? baseURL.host ?? "localhost"

        // The user handle must be the server's: discoverable sign-in returns
        // it, and the server maps it back to the account.
        guard let userHandle = (options["user"] as? [String: Any])?["id"] as? String,
              let userID = Data(base64URLEncoded: userHandle)
        else {
            throw APIError.server("Invalid user handle received for passkey registration.")
        }

        let registration = try await passkeyCoordinator.registerPasskey(
            relyingPartyID: rpID,
            challenge: challenge,
            userName: email,
            userID: userID
        )

        let finish = try Components.Schemas.PasskeyFinishRequest(
            challengeId: ceremony.challengeId,
            credential: .init(additionalProperties: .init(json: registration.credentialJSON))
        )
        let session = try await NorthAPI.call { try await api.finishPasskeyRegistration(body: .json(finish)).created.body.json }
        return try await store(session)
    }

    // MARK: Sign out

    public func logout() async {
        _ = try? await NorthAPI.call { try await api.logOut().noContent }
        await sessionManager.logout()
    }

    // MARK: Helpers

    private func store(_ session: AuthSession) async throws -> AuthSession {
        try await sessionManager.storeSession(token: session.token, user: session.user, expiresAt: session.expiresAt)
        return session
    }

    private static func challenge(in options: [String: Any]) throws -> Data {
        guard let encoded = options["challenge"] as? String, let challenge = Data(base64URLEncoded: encoded) else {
            throw APIError.server("Invalid passkey challenge from the server.")
        }
        return challenge
    }

    @MainActor
    private static func presentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
