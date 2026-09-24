import Foundation
import GoogleSignIn
import UIKit

public protocol AuthServicing: Sendable {
    func currentUser() async throws -> MeResponseDTO
    func today() async throws -> TodayResponseDTO
    func completeOnboarding(_ request: OnboardingRequestDTO) async throws -> OnboardingResponseDTO
    func login(email: String, password: String) async throws -> AuthResponseDTO
    func signup(email: String, password: String, passwordConfirmation: String, displayName: String) async throws -> AuthResponseDTO
    func forgotPassword(email: String) async throws
    @MainActor
    func signInWithGoogle() async throws -> AuthResponseDTO
    @MainActor
    func signInWithApple() async throws -> AuthResponseDTO
    @MainActor
    func signInWithPasskey() async throws -> AuthResponseDTO
    @MainActor
    func registerPasskey(email: String, displayName: String) async throws -> AuthResponseDTO
    func logout() async
}

public final class AuthService: AuthServicing, @unchecked Sendable {
    public static let shared = AuthService()

    private let httpClient: AuthHTTPClient
    private let sessionManager: AuthSessionManaging
    private let webAuthenticator: OAuthWebAuthenticating
    private let appleCoordinator: AppleSignInCoordinating
    private let passkeyCoordinator: PasskeyCoordinating
    private let baseURL: URL

    public init(
        baseURL: URL = URL(string: "http://localhost:8090")!,
        httpClient: AuthHTTPClient? = nil,
        sessionManager: AuthSessionManaging = AuthSessionManager.shared,
        webAuthenticator: OAuthWebAuthenticating = OAuthWebAuthenticator(),
        appleCoordinator: AppleSignInCoordinating = AppleSignInCoordinator(),
        passkeyCoordinator: PasskeyCoordinating = PasskeyCoordinator()
    ) {
        self.baseURL = baseURL
        self.sessionManager = sessionManager
        self.httpClient = httpClient ?? AuthHTTPClient(baseURL: baseURL, authTokenProvider: {
            try? await sessionManager.validAccessToken()
        })
        self.webAuthenticator = webAuthenticator
        self.appleCoordinator = appleCoordinator
        self.passkeyCoordinator = passkeyCoordinator
    }

    public func login(email: String, password: String) async throws -> AuthResponseDTO {
        let response = try await httpClient.login(LoginRequestDTO(email: email, password: password))
        try await sessionManager.storeSession(token: response.token, user: response.user, expiresAt: response.expiresAt)
        return response
    }

    public func currentUser() async throws -> MeResponseDTO {
        try await httpClient.me()
    }

    public func today() async throws -> TodayResponseDTO {
        try await httpClient.today()
    }

    public func completeOnboarding(_ request: OnboardingRequestDTO) async throws -> OnboardingResponseDTO {
        try await httpClient.completeOnboarding(request)
    }

    public func signup(email: String, password: String, passwordConfirmation: String, displayName: String) async throws -> AuthResponseDTO {
        let response = try await httpClient.signup(SignupRequestDTO(
            email: email,
            password: password,
            passwordConfirmation: passwordConfirmation,
            displayName: displayName
        ))
        try await sessionManager.storeSession(token: response.token, user: response.user, expiresAt: response.expiresAt)
        return response
    }

    public func forgotPassword(email: String) async throws {
        try await httpClient.forgotPassword(ForgotPasswordRequestDTO(email: email))
    }

    @MainActor
    public func signInWithGoogle() async throws -> AuthResponseDTO {
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
        let response = try await httpClient.googleAuth(GoogleAuthRequestDTO(idToken: idToken))
        try await sessionManager.storeSession(token: response.token, user: response.user, expiresAt: response.expiresAt)
        return response
    }

    @MainActor
    public func signInWithApple() async throws -> AuthResponseDTO {
        let result = try await appleCoordinator.signIn()
        let request = AppleAuthRequestDTO(
            identityToken: result.identityToken,
            authorizationCode: result.authorizationCode,
            nonce: result.rawNonce,
            fullName: result.fullName,
            email: result.email
        )
        let response = try await httpClient.appleAuth(request)
        try await sessionManager.storeSession(token: response.token, user: response.user, expiresAt: response.expiresAt)
        return response
    }

    @MainActor
    public func signInWithPasskey() async throws -> AuthResponseDTO {
        let beginResponse = try await httpClient.passkeyLoginBegin(PasskeyLoginBeginRequestDTO())
        let challengeString = (beginResponse.publicKey["challenge"]?.value as? String) ?? ""
        guard let challengeData = Data(base64URLEncoded: challengeString) ?? challengeString.data(using: .utf8) else {
            throw APIError.server("Invalid challenge received for passkey sign-in.")
        }

        let rpID = (beginResponse.publicKey["rpId"]?.value as? String) ?? baseURL.host ?? "localhost"
        let assertionResult = try await passkeyCoordinator.loginWithPasskey(relyingPartyID: rpID, challenge: challengeData)

        let finishRequest = PasskeyCeremonyFinishRequestDTO(
            challengeId: beginResponse.challengeId,
            credential: assertionResult.toDictionary()
        )
        let response = try await httpClient.passkeyLoginFinish(finishRequest)
        try await sessionManager.storeSession(token: response.token, user: response.user, expiresAt: response.expiresAt)
        return response
    }

    @MainActor
    public func registerPasskey(email: String, displayName: String) async throws -> AuthResponseDTO {
        let beginRequest = PasskeyRegisterBeginRequestDTO(email: email, displayName: displayName)
        let beginResponse = try await httpClient.passkeyRegisterBegin(beginRequest)

        let challengeString = (beginResponse.publicKey["challenge"]?.value as? String) ?? ""
        guard let challengeData = Data(base64URLEncoded: challengeString) ?? challengeString.data(using: .utf8) else {
            throw APIError.server("Invalid challenge received for passkey registration.")
        }

        let rpID = (beginResponse.publicKey["rp"]?.value as? [String: Any])?["id"] as? String ?? baseURL.host ?? "localhost"
        let userID = UUID().uuidString.data(using: .utf8) ?? Data()

        let registrationResult = try await passkeyCoordinator.registerPasskey(
            relyingPartyID: rpID,
            challenge: challengeData,
            userName: email,
            userID: userID
        )

        let finishRequest = PasskeyCeremonyFinishRequestDTO(
            challengeId: beginResponse.challengeId,
            credential: registrationResult.toDictionary()
        )
        let response = try await httpClient.passkeyRegisterFinish(finishRequest)
        try await sessionManager.storeSession(token: response.token, user: response.user, expiresAt: response.expiresAt)
        return response
    }

    public func logout() async {
        try? await httpClient.logout()
        await sessionManager.logout()
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
