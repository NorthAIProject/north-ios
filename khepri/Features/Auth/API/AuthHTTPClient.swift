import Foundation

public final class AuthHTTPClient: Sendable {
    private let client: BaseHTTPClient

    public init(baseURL: URL, session: any HTTPClientSession = URLSession.shared, authTokenProvider: (@Sendable () async -> String?)? = nil) {
        self.client = BaseHTTPClient(baseURL: baseURL, session: session, authTokenProvider: authTokenProvider)
    }

    public func login(_ request: LoginRequestDTO) async throws -> AuthResponseDTO {
        try await client.call(LoginEndpoint(request: request))
    }

    public func signup(_ request: SignupRequestDTO) async throws -> AuthResponseDTO {
        try await client.call(SignupEndpoint(request: request))
    }

    public func forgotPassword(_ request: ForgotPasswordRequestDTO) async throws {
        _ = try await client.call(ForgotPasswordEndpoint(request: request))
    }

    public func googleAuth(_ request: GoogleAuthRequestDTO) async throws -> AuthResponseDTO {
        try await client.call(GoogleAuthEndpoint(request: request))
    }

    public func appleAuth(_ request: AppleAuthRequestDTO) async throws -> AuthResponseDTO {
        try await client.call(AppleAuthEndpoint(request: request))
    }

    public func passkeyRegisterBegin(_ request: PasskeyRegisterBeginRequestDTO) async throws -> PasskeyCeremonyDTO {
        try await client.call(PasskeyRegisterBeginEndpoint(request: request))
    }

    public func passkeyRegisterFinish(_ request: PasskeyCeremonyFinishRequestDTO) async throws -> AuthResponseDTO {
        try await client.call(PasskeyRegisterFinishEndpoint(request: request))
    }

    public func passkeyLoginBegin(_ request: PasskeyLoginBeginRequestDTO) async throws -> PasskeyCeremonyDTO {
        try await client.call(PasskeyLoginBeginEndpoint(request: request))
    }

    public func passkeyLoginFinish(_ request: PasskeyCeremonyFinishRequestDTO) async throws -> AuthResponseDTO {
        try await client.call(PasskeyLoginFinishEndpoint(request: request))
    }

    public func logout() async throws {
        _ = try await client.call(LogoutEndpoint())
    }

    public func me() async throws -> MeResponseDTO {
        try await client.call(MeEndpoint())
    }

    public func completeOnboarding(_ request: OnboardingRequestDTO) async throws -> OnboardingResponseDTO {
        try await client.call(OnboardingEndpoint(request: request))
    }

    public func today() async throws -> TodayResponseDTO {
        try await client.call(TodayEndpoint())
    }
}
