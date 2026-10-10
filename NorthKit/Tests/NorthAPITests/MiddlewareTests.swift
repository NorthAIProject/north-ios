import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import Testing
@testable import NorthAPI

/// Drives the real generated client against a canned transport, so these
/// tests cover the middlewares exactly as the app wires them.
struct MiddlewareTests {
    @Test func sendsTheBearerTokenToPrivateOperations() async throws {
        let transport = CannedTransport(status: .ok, json: Self.meJSON)
        _ = try await NorthAPI.call { try await client(transport).getMe().ok.body.json }
        #expect(transport.lastRequest?.headerFields[.authorization] == "Bearer session-token")
    }

    @Test func sendsThePhonesLanguages() async throws {
        #expect(LanguageMiddleware.header(for: ["pt-PT", "en-GB", "es", "fr"]) == "pt-PT, en-GB;q=0.9, es;q=0.8")
        #expect(LanguageMiddleware.header(for: []) == nil)

        let transport = CannedTransport(status: .ok, json: Self.meJSON)
        _ = try await NorthAPI.call { try await client(transport).getMe().ok.body.json }
        #expect(transport.lastRequest?.headerFields[.acceptLanguage] == "pt-PT, en-GB;q=0.9")
    }

    @Test func keepsTheTokenOffSignIn() async throws {
        let transport = CannedTransport(status: .ok, json: Self.authJSON)
        _ = try await NorthAPI.call {
            try await client(transport).logIn(body: .json(.init(email: "ana@example.com", password: "pw"))).ok.body.json
        }
        #expect(transport.lastRequest?.headerFields[.authorization] == nil)
    }

    @Test func rejectedTokenSignsOutAndCarriesTheServerMessage() async throws {
        let signedOut = Mutex(false)
        let transport = CannedTransport(status: .unauthorized, json: #"{"error":{"message":"That token is not valid."}}"#)
        let api = client(transport, onUnauthorized: { signedOut.withLock { $0 = true } })

        await #expect(throws: APIError.unauthorized("That token is not valid.")) {
            try await NorthAPI.call { try await api.getMe().ok.body.json }
        }
        #expect(signedOut.withLock { $0 })
    }

    @Test func fieldErrorsSurviveTheTrip() async throws {
        let transport = CannedTransport(
            status: .unprocessableContent,
            json: #"{"error":{"message":"Please complete the required fields.","fields":{"focusAreas":"Pick at least one."}}}"#
        )
        await #expect(throws: APIError.fieldValidation(message: "Please complete the required fields.", fields: ["focusAreas": "Pick at least one."])) {
            try await NorthAPI.call {
                try await client(transport).completeOnboarding(body: .json(.init(focusAreas: [], coachingStyle: "direct"))).ok.body.json
            }
        }
    }

    @Test func aMissingThingIsNotFoundWithTheServersWords() async throws {
        let transport = CannedTransport(status: .notFound, json: #"{"error":{"message":"No intake yet."}}"#)
        await #expect(throws: APIError.notFound("No intake yet.")) {
            try await NorthAPI.call { try await client(transport).getMe().ok.body.json }
        }
    }

    @Test func anErrorWithoutABodyKeepsItsStatus() async throws {
        let transport = CannedTransport(status: .badGateway, json: nil)
        await #expect(throws: APIError.invalidStatus(502)) {
            try await NorthAPI.call { try await client(transport).getMe().ok.body.json }
        }
    }

    /// A 409 whose body is a plan, not an error, reaches the generated client
    /// as the operation's documented conflict case.
    @Test func aDocumentedNonErrorBodyPassesThrough() async throws {
        let plan = #"{"id":"abababab-abab-abab-abab-abababababab","name":"Base","rationale":"","weeksTotal":4,"days":[],"problems":[],"source":"edited","createdAt":"2026-09-24T07:15:00Z"}"#
        let transport = CannedTransport(status: .conflict, json: plan)
        let output = try await NorthAPI.call {
            try await client(transport).setDayStartTime(path: .init(planID: "p", day: 0), body: .json(.init(startTime: "07:00")))
        }
        guard case .conflict(let conflict) = output else {
            Issue.record("expected the conflict case, got \(output)")
            return
        }
        #expect(try conflict.body.json.name == "Base")
    }

    /// A chat attachment goes up under its real media type and filename, and
    /// still satisfies the operation's required `file` part.
    @Test func uploadsAFileUnderItsOwnMediaType() async throws {
        let stored = #"{"mediaId":"55555555-5555-5555-5555-555555555555","kind":"file","mimeType":"application/pdf","name":"dieta.pdf"}"#
        let transport = CannedTransport(status: .created, json: stored)
        let part = MultipartRawPart.file(filename: "dieta.pdf", contentType: "application/pdf", data: Data("%PDF-1.7".utf8))
        let attachment = try await NorthAPI.call {
            try await client(transport).uploadChatAttachment(path: .init(id: "c1"), body: .multipartForm([.undocumented(part)])).created.body.json
        }
        #expect(attachment.name == "dieta.pdf")
        let body = String(decoding: try #require(transport.lastBody), as: UTF8.self)
        #expect(body.contains(#"content-disposition: form-data; filename="dieta.pdf"; name="file""#))
        #expect(body.contains("content-type: application/pdf"))
        #expect(body.contains("%PDF-1.7"))
    }

    // MARK: - A session that cannot be read

    /// A locked phone cannot read the Keychain. That is not a signed-out
    /// person: nothing goes out, nobody is signed out, and the caller learns
    /// why.
    @Test func anUnreadableTokenSendsNothingAndKeepsTheSession() async throws {
        let signedOut = Mutex(false)
        let transport = CannedTransport(status: .unauthorized, json: #"{"error":{"message":"No token."}}"#)
        let api = client(transport, token: { throw LockedKeychain() }, onUnauthorized: { signedOut.withLock { $0 = true } })

        await #expect(throws: APIError.locked) {
            try await NorthAPI.call { try await api.getMe().ok.body.json }
        }
        #expect(transport.requestCount == 0, "an unauthenticated request must not go out")
        #expect(!signedOut.withLock { $0 })
        #expect(APIError.locked.errorDescription == "Unlock your phone to continue.")
    }

    /// Only a token the server saw and refused ends the session.
    @Test func a401WithoutATokenDoesNotSignOut() async throws {
        let signedOut = Mutex(false)
        let transport = CannedTransport(status: .unauthorized, json: #"{"error":{"message":"Sign in first."}}"#)
        let api = client(transport, token: { nil }, onUnauthorized: { signedOut.withLock { $0 = true } })

        await #expect(throws: APIError.unauthorized("Sign in first.")) {
            try await NorthAPI.call { try await api.getMe().ok.body.json }
        }
        #expect(transport.lastRequest?.headerFields[.authorization] == nil)
        #expect(!signedOut.withLock { $0 })
    }

    private func client(
        _ transport: CannedTransport,
        token: @escaping @Sendable () async throws -> String? = { "session-token" },
        onUnauthorized: @escaping @Sendable () -> Void = {}
    ) -> Client {
        Client(
            serverURL: URL(string: "https://example.com/api/v1")!,
            configuration: NorthAPI.configuration,
            transport: transport,
            middlewares: [
                ErrorMappingMiddleware(),
                LanguageMiddleware(preferred: { ["pt-PT", "en-GB"] }),
                BearerAuthMiddleware(token: token, onUnauthorized: { onUnauthorized() }),
            ]
        )
    }

    static let meJSON = #"{"user":{"id":"22222222-2222-2222-2222-222222222222","email":"ana@example.com","displayName":"Ana","timezone":"UTC","needsOnboarding":false}}"#
    static let authJSON = #"{"token":"t","expiresAt":"2026-10-24T09:30:00Z","user":{"id":"22222222-2222-2222-2222-222222222222","email":"ana@example.com","displayName":"Ana","timezone":"UTC","needsOnboarding":false}}"#
}

/// The Keychain refusing a read, as it does while the phone is locked.
struct LockedKeychain: Error {}

/// Answers every request with one status and body, and remembers the
/// request and what it sent. `failures` are thrown first, one per request,
/// as a dropped connection would.
final class CannedTransport: ClientTransport, Sendable {
    private let status: HTTPResponse.Status
    private let json: String?
    private let recorded = Mutex<HTTPRequest?>(nil)
    private let recordedBody = Mutex<Data?>(nil)
    private let pendingFailures: Mutex<[URLError]>
    private let requests = Mutex(0)

    init(status: HTTPResponse.Status, json: String?, failures: [URLError] = []) {
        self.status = status
        self.json = json
        pendingFailures = Mutex(failures)
    }

    var lastRequest: HTTPRequest? { recorded.withLock { $0 } }
    var lastBody: Data? { recordedBody.withLock { $0 } }
    /// Every request that reached the transport, failed ones included.
    var requestCount: Int { requests.withLock { $0 } }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        requests.withLock { $0 += 1 }
        if let failure = pendingFailures.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) {
            throw failure
        }
        recorded.withLock { $0 = request }
        if let body {
            let bytes = try await Data(collecting: body, upTo: 1 << 20)
            recordedBody.withLock { $0 = bytes }
        }
        var response = HTTPResponse(status: status)
        guard let json else { return (response, nil) }
        response.headerFields[.contentType] = "application/json; charset=utf-8"
        return (response, HTTPBody(json))
    }
}
