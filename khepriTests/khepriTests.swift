//
//  khepriTests.swift
//  khepriTests
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import Foundation
import HTTPTypes
import NorthAPI
import OpenAPIRuntime
import Synchronization
import Testing
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
        let store = MemoryStore()
        let sessions = AuthSessionManager(secureStore: store)

        try await sessions.storeSession(token: "live", user: nil, expiresAt: Date().addingTimeInterval(3600))
        #expect(try await sessions.validAccessToken() == "live")

        try await sessions.storeSession(token: "stale", user: nil, expiresAt: Date().addingTimeInterval(-60))
        #expect(try await sessions.validAccessToken() == nil)
        #expect(store.storage.isEmpty)
    }

    @Test func loginStoresTheSessionTheServerReturns() async throws {
        let store = MemoryStore()
        let sessions = AuthSessionManager(secureStore: store)
        let transport = RecordingTransport(json: """
        {"token":"server-token","expiresAt":"2026-10-24T09:30:00.123456789Z",
         "user":{"id":"22222222-2222-2222-2222-222222222222","email":"ana@example.com",
                 "displayName":"Ana","timezone":"Europe/Lisbon","needsOnboarding":true}}
        """)
        let service = AuthService(
            api: NorthAPI.client(baseURL: URL(string: "https://example.com")!, token: { nil }, transport: transport),
            sessionManager: sessions
        )

        let session = try await service.login(email: "ana@example.com", password: "correct horse")

        #expect(session.user.needsOnboarding)
        #expect(try await sessions.validAccessToken() == "server-token")
        #expect(transport.lastPath == "/api/v1/auth/login")
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

final class MemoryStore: SecureStringStoring, @unchecked Sendable {
    var storage: [String: String] = [:]
    func string(for key: String) throws -> String? { storage[key] }
    func setString(_ value: String, for key: String) throws { storage[key] = value }
    func removeValue(for key: String) throws { storage.removeValue(forKey: key) }
}

/// Answers every request with 200 and one JSON body, and records the path.
final class RecordingTransport: ClientTransport, Sendable {
    private let json: String
    private let path = Mutex<String?>(nil)

    init(json: String) { self.json = json }

    var lastPath: String? { path.withLock { $0 } }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        path.withLock { $0 = baseURL.path() + (request.path ?? "") }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(json))
    }
}
