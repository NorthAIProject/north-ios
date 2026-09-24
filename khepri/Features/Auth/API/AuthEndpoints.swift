import Foundation

public struct LoginEndpoint: Endpoint {
    public typealias Response = AuthResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/login"
    public let bodyData: Data?

    public init(request: LoginRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct SignupEndpoint: Endpoint {
    public typealias Response = AuthResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/signup"
    public let bodyData: Data?

    public init(request: SignupRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct ForgotPasswordEndpoint: Endpoint {
    public typealias Response = EmptyResponse
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/forgot-password"
    public let bodyData: Data?

    public init(request: ForgotPasswordRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct GoogleAuthEndpoint: Endpoint {
    public typealias Response = AuthResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/google"
    public let bodyData: Data?

    public init(request: GoogleAuthRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct AppleAuthEndpoint: Endpoint {
    public typealias Response = AuthResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/apple"
    public let bodyData: Data?

    public init(request: AppleAuthRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct PasskeyRegisterBeginEndpoint: Endpoint {
    public typealias Response = PasskeyCeremonyDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/passkey/register/begin"
    public let bodyData: Data?

    public init(request: PasskeyRegisterBeginRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct PasskeyRegisterFinishEndpoint: Endpoint {
    public typealias Response = AuthResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/passkey/register/finish"
    public let bodyData: Data?

    public init(request: PasskeyCeremonyFinishRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct PasskeyLoginBeginEndpoint: Endpoint {
    public typealias Response = PasskeyCeremonyDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/passkey/login/begin"
    public let bodyData: Data?

    public init(request: PasskeyLoginBeginRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct PasskeyLoginFinishEndpoint: Endpoint {
    public typealias Response = AuthResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/passkey/login/finish"
    public let bodyData: Data?

    public init(request: PasskeyCeremonyFinishRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct MeEndpoint: Endpoint {
    public typealias Response = MeResponseDTO
    public let method: HTTPMethod = .get
    public let path: String = "/api/v1/me"

    public init() {}
}

public struct OnboardingEndpoint: Endpoint {
    public typealias Response = OnboardingResponseDTO
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/onboarding"
    public let bodyData: Data?

    public init(request: OnboardingRequestDTO) {
        let encoder = JSONEncoder()
        self.bodyData = try? encoder.encode(request)
    }
}

public struct TodayEndpoint: Endpoint {
    public typealias Response = TodayResponseDTO
    public let method: HTTPMethod = .get
    public let path: String = "/api/v1/today"

    public init() {}
}

public struct LogoutEndpoint: Endpoint {
    public typealias Response = EmptyResponse
    public let method: HTTPMethod = .post
    public let path: String = "/api/v1/auth/logout"

    public init() {}
}
