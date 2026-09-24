import Foundation

// MARK: - User & Session Models

public struct UserDTO: Sendable, Equatable {
    public let id: String
    public let email: String
    public let displayName: String?
    public let timezone: String?
    public let needsOnboarding: Bool

    public init(id: String, email: String, displayName: String? = nil, timezone: String? = nil, needsOnboarding: Bool = false) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.timezone = timezone
        self.needsOnboarding = needsOnboarding
    }
}

extension UserDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.email = try container.decode(String.self, forKey: .email)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        self.needsOnboarding = try container.decodeIfPresent(Bool.self, forKey: .needsOnboarding) ?? false
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encode(needsOnboarding, forKey: .needsOnboarding)
    }

    private enum CodingKeys: String, CodingKey {
        case id, email, displayName, timezone, needsOnboarding
    }
}

public struct MeResponseDTO: Sendable, Equatable {
    public let user: UserDTO
}

public struct OnboardingRequestDTO: Sendable, Equatable {
    public let focusAreas: [String]
    public let coachingStyle: String
    public let coachingStyleCustom: String
    public let nearTermGoal: String

    public init(focusAreas: [String], coachingStyle: String, coachingStyleCustom: String = "", nearTermGoal: String) {
        self.focusAreas = focusAreas
        self.coachingStyle = coachingStyle
        self.coachingStyleCustom = coachingStyleCustom
        self.nearTermGoal = nearTermGoal
    }
}

extension OnboardingRequestDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.focusAreas = try container.decode([String].self, forKey: .focusAreas)
        self.coachingStyle = try container.decode(String.self, forKey: .coachingStyle)
        self.coachingStyleCustom = try container.decodeIfPresent(String.self, forKey: .coachingStyleCustom) ?? ""
        self.nearTermGoal = try container.decode(String.self, forKey: .nearTermGoal)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focusAreas, forKey: .focusAreas)
        try container.encode(coachingStyle, forKey: .coachingStyle)
        try container.encode(coachingStyleCustom, forKey: .coachingStyleCustom)
        try container.encode(nearTermGoal, forKey: .nearTermGoal)
    }

    private enum CodingKeys: String, CodingKey {
        case focusAreas, coachingStyle, coachingStyleCustom, nearTermGoal
    }
}

public struct OnboardingResponseDTO: Sendable, Equatable {
    public let user: UserDTO
    public let threadId: String?
}

extension OnboardingResponseDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try container.decode(UserDTO.self, forKey: .user)
        self.threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user, forKey: .user)
        try container.encodeIfPresent(threadId, forKey: .threadId)
    }

    private enum CodingKeys: String, CodingKey {
        case user, threadId
    }
}

extension MeResponseDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try container.decode(UserDTO.self, forKey: .user)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user, forKey: .user)
    }

    private enum CodingKeys: String, CodingKey {
        case user
    }
}

public struct AuthResponseDTO: Sendable, Equatable {
    public let token: String
    public let expiresAt: Date?
    public let user: UserDTO?

    public init(token: String, expiresAt: Date? = nil, user: UserDTO? = nil) {
        self.token = token
        self.expiresAt = expiresAt
        self.user = user
    }
}

extension AuthResponseDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.token = try container.decode(String.self, forKey: .token)
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        self.user = try container.decodeIfPresent(UserDTO.self, forKey: .user)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(user, forKey: .user)
    }

    private enum CodingKeys: String, CodingKey {
        case token, expiresAt, user
    }
}

// MARK: - Email / Password Request DTOs

public struct LoginRequestDTO: Codable, Sendable, Equatable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct SignupRequestDTO: Codable, Sendable, Equatable {
    public let email: String
    public let password: String
    public let passwordConfirmation: String
    public let displayName: String
    public let timezone: String

    public init(
        email: String,
        password: String,
        passwordConfirmation: String,
        displayName: String,
        timezone: String = TimeZone.current.identifier
    ) {
        self.email = email
        self.password = password
        self.passwordConfirmation = passwordConfirmation
        self.displayName = displayName
        self.timezone = timezone
    }
}

public struct ForgotPasswordRequestDTO: Codable, Sendable, Equatable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

// MARK: - OAuth DTOs

public struct OAuthStartResponseDTO: Codable, Sendable, Equatable {
    public let flowId: String?
    public let authorizationUrl: String

    public init(flowId: String? = nil, authorizationUrl: String) {
        self.flowId = flowId
        self.authorizationUrl = authorizationUrl
    }
}

public struct GoogleAuthRequestDTO: Codable, Sendable, Equatable {
    public let idToken: String

    public init(idToken: String) {
        self.idToken = idToken
    }
}

public struct AppleAuthRequestDTO: Codable, Sendable, Equatable {
    public let identityToken: String
    public let authorizationCode: String
    public let nonce: String
    public let fullName: String?
    public let email: String?

    public init(
        identityToken: String,
        authorizationCode: String,
        nonce: String,
        fullName: String? = nil,
        email: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
        self.fullName = fullName
        self.email = email
    }
}

// MARK: - Passkey / WebAuthn DTOs

public struct PasskeyCeremonyDTO: Sendable {
    public let challengeId: String
    public let publicKey: [String: AnyCodable]

    public init(challengeId: String, publicKey: [String: AnyCodable]) {
        self.challengeId = challengeId
        self.publicKey = publicKey
    }
}

extension PasskeyCeremonyDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try container.decode(String.self, forKey: .challengeId)
        self.publicKey = try container.decode([String: AnyCodable].self, forKey: .publicKey)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(publicKey, forKey: .publicKey)
    }

    private enum CodingKeys: String, CodingKey {
        case challengeId, publicKey
    }
}

public struct PasskeyRegisterBeginRequestDTO: Codable, Sendable {
    public let email: String
    public let displayName: String
    public let timezone: String

    public init(email: String, displayName: String, timezone: String = TimeZone.current.identifier) {
        self.email = email
        self.displayName = displayName
        self.timezone = timezone
    }
}

public struct PasskeyLoginBeginRequestDTO: Codable, Sendable {
    public let email: String?

    public init(email: String? = nil) {
        self.email = email
    }
}

public struct PasskeyCeremonyFinishRequestDTO: Codable, Sendable {
    public let challengeId: String
    public let credential: [String: AnyCodable]

    public init(challengeId: String, credential: [String: AnyCodable]) {
        self.challengeId = challengeId
        self.credential = credential
    }
}

// MARK: - AnyCodable Helper for arbitrary WebAuthn options and credentials

public struct AnyCodable: @unchecked Sendable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

extension AnyCodable: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
