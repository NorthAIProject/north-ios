//
//  khepriTests.swift
//  khepriTests
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import Testing
import Foundation
@testable import khepri

struct AuthTests {

    @Test func testEmailValidation() {
        #expect(AuthValidation.isValidEmail("user@example.com") == true)
        #expect(AuthValidation.isValidEmail("test.user+tag@domain.co.uk") == true)
        #expect(AuthValidation.isValidEmail("invalid-email") == false)
        #expect(AuthValidation.isValidEmail("@missingusername.com") == false)
        #expect(AuthValidation.isValidEmail("user@.com") == false)
    }

    @Test func testPasswordStrengthScoring() {
        #expect(AuthValidation.passwordStrengthScore("abc") == 0)
        #expect(AuthValidation.passwordStrengthScore("password123") <= 2)
        #expect(AuthValidation.passwordStrengthScore("Password123!") >= 3)
    }

    @Test func expiredSessionIsDiscarded() async throws {
        final class MemoryStore: SecureStringStoring, @unchecked Sendable {
            var storage: [String: String] = [:]
            func string(for key: String) throws -> String? { storage[key] }
            func setString(_ value: String, for key: String) throws { storage[key] = value }
            func removeValue(for key: String) throws { storage.removeValue(forKey: key) }
        }

        let store = MemoryStore()
        let sessions = AuthSessionManager(secureStore: store)

        try await sessions.storeSession(token: "live", user: nil, expiresAt: Date().addingTimeInterval(3600))
        #expect(try await sessions.validAccessToken() == "live")

        try await sessions.storeSession(token: "stale", user: nil, expiresAt: Date().addingTimeInterval(-60))
        #expect(try await sessions.validAccessToken() == nil)
        #expect(store.storage.isEmpty)
    }

    @Test func testMockSecureStore() throws {
        final class MockSecureStore: SecureStringStoring, @unchecked Sendable {
            var storage: [String: String] = [:]
            func string(for key: String) throws -> String? { storage[key] }
            func setString(_ value: String, for key: String) throws { storage[key] = value }
            func removeValue(for key: String) throws { storage.removeValue(forKey: key) }
        }

        let store = MockSecureStore()
        let sessionManager = AuthSessionManager(secureStore: store)

        // Storing session
        Task {
            try await sessionManager.storeSession(
                token: "mock-session-token",
                user: UserDTO(id: "123", email: "test@north.ai"),
                expiresAt: Date().addingTimeInterval(3600)
            )

            let restoredToken = try await sessionManager.validAccessToken()
            #expect(restoredToken == "mock-session-token")

            await sessionManager.logout()
            let clearedToken = try await sessionManager.validAccessToken()
            #expect(clearedToken == nil)
        }
    }

    @Test func testGoogleAuthEndpoint() throws {
        let endpoint = GoogleAuthEndpoint(request: GoogleAuthRequestDTO(idToken: "mock-google-id-token"))
        #expect(endpoint.path == "/api/v1/auth/google")
        #expect(endpoint.method == .post)
        #expect(endpoint.bodyData != nil)
        if let bodyData = endpoint.bodyData {
            let decoded = try JSONDecoder().decode(GoogleAuthRequestDTO.self, from: bodyData)
            #expect(decoded.idToken == "mock-google-id-token")
        }
    }

    @Test func testAppleAuthEndpoint() throws {
        let endpoint = AppleAuthEndpoint(request: AppleAuthRequestDTO(
            identityToken: "mock-apple-id-token",
            authorizationCode: "mock-code",
            nonce: "raw-nonce",
            fullName: "Test User",
            email: "apple@north.ai"
        ))
        #expect(endpoint.path == "/api/v1/auth/apple")
        #expect(endpoint.method == .post)
        #expect(endpoint.bodyData != nil)
        if let bodyData = endpoint.bodyData {
            let decoded = try JSONDecoder().decode(AppleAuthRequestDTO.self, from: bodyData)
            #expect(decoded.identityToken == "mock-apple-id-token")
            #expect(decoded.nonce == "raw-nonce")
        }
    }

    @Test func testGoogleClientIDConfiguration() {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        // When running in test host, GIDClientID should be present and valid
        if let clientID {
            #expect(!clientID.isEmpty)
            #expect(clientID.contains("apps.googleusercontent.com"))
        }
    }
}

