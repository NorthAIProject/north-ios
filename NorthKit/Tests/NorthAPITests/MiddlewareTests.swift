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

    private func client(_ transport: CannedTransport, onUnauthorized: @escaping @Sendable () -> Void = {}) -> Client {
        Client(
            serverURL: URL(string: "https://example.com/api/v1")!,
            configuration: NorthAPI.configuration,
            transport: transport,
            middlewares: [
                ErrorMappingMiddleware(),
                BearerAuthMiddleware(token: { "session-token" }, onUnauthorized: { onUnauthorized() }),
            ]
        )
    }

    static let meJSON = #"{"user":{"id":"22222222-2222-2222-2222-222222222222","email":"ana@example.com","displayName":"Ana","timezone":"UTC","needsOnboarding":false}}"#
    static let authJSON = #"{"token":"t","expiresAt":"2026-10-24T09:30:00Z","user":{"id":"22222222-2222-2222-2222-222222222222","email":"ana@example.com","displayName":"Ana","timezone":"UTC","needsOnboarding":false}}"#
}

/// Answers every request with one status and body, and remembers the request.
final class CannedTransport: ClientTransport, Sendable {
    private let status: HTTPResponse.Status
    private let json: String?
    private let recorded = Mutex<HTTPRequest?>(nil)

    init(status: HTTPResponse.Status, json: String?) {
        self.status = status
        self.json = json
    }

    var lastRequest: HTTPRequest? { recorded.withLock { $0 } }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        recorded.withLock { $0 = request }
        var response = HTTPResponse(status: status)
        guard let json else { return (response, nil) }
        response.headerFields[.contentType] = "application/json; charset=utf-8"
        return (response, HTTPBody(json))
    }
}
