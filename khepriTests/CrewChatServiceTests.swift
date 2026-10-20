import Foundation
import HTTPTypes
import Synchronization
import NorthAPI
import OpenAPIRuntime
import Testing
@testable import khepri

/// Records each request's method, path with query, Accept header and body,
/// and answers with one canned status and body.
final class CrewRequestRecorder: ClientTransport, Sendable {
    struct Seen: Sendable {
        var method: HTTPRequest.Method
        var path: String
        var accept: String?
        var body: String
    }

    private let status: HTTPResponse.Status
    private let contentType: String
    private let reply: String
    private let seen = Mutex<[Seen]>([])

    init(status: HTTPResponse.Status = .ok, contentType: String = "application/json", reply: String = "{}") {
        self.status = status
        self.contentType = contentType
        self.reply = reply
    }

    var requests: [Seen] { seen.withLock { $0 } }
    var last: Seen? { requests.last }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        var sent = ""
        if let body { sent = String(decoding: try await Data(collecting: body, upTo: 1 << 20), as: UTF8.self) }
        seen.withLock {
            $0.append(Seen(method: request.method, path: baseURL.path() + (request.path ?? ""), accept: request.headerFields[.accept], body: sent))
        }
        var response = HTTPResponse(status: status)
        if status != .noContent { response.headerFields[.contentType] = contentType }
        return (response, status == .noContent ? nil : HTTPBody(reply))
    }
}

struct CrewChatServiceTests {
    private let crew = "11111111-1111-1111-1111-111111111111"
    private let channel = "22222222-2222-2222-2222-222222222222"
    private let message = "33333333-3333-3333-3333-333333333333"

    private func service(_ transport: CrewRequestRecorder) -> CrewChatService {
        let client = NorthAPI.client(baseURL: URL(string: "https://example.com")!, token: { nil }, transport: transport)
        return CrewChatService(api: client)
    }

    @Test func sendCarriesClientID() async throws {
        let transport = CrewRequestRecorder(status: .created, reply: #"{"id":"\#(message)"}"#)
        let clientID = UUID()

        let sent = try await service(transport).send(crew, channel: channel, body: "hi", replyTo: nil, clientID: clientID)

        #expect(sent.id == message)
        let seen = try #require(transport.last)
        #expect(seen.method == .post)
        #expect(seen.path.hasSuffix("/crews/\(crew)/channels/\(channel)/messages"))
        let json = try #require(JSONSerialization.jsonObject(with: Data(seen.body.utf8)) as? [String: Any])
        #expect(json["clientId"] as? String == clientID.uuidString)
        #expect(json["body"] as? String == "hi")
    }

    @Test func reactUsesKeyPath() async throws {
        let transport = CrewRequestRecorder(status: .noContent)
        let chat = service(transport)

        try await chat.react(crew, id: message, emoji: "fire", on: true)
        try await chat.react(crew, id: message, emoji: "fire", on: false)

        let tail = "/crews/\(crew)/messages/\(message)/reactions/fire"
        #expect(transport.requests.map(\.method) == [.put, .delete])
        #expect(transport.requests.allSatisfy { $0.path.hasSuffix(tail) })
    }

    @Test func messagesAfterQuery() async throws {
        let transport = CrewRequestRecorder(reply: #"{"messages":[]}"#)

        _ = try await service(transport).messages(crew, channel: channel, before: nil, after: 41)

        let path = try #require(transport.last?.path)
        #expect(path.contains("after=41"))
        #expect(!path.contains("before"))
    }

    @Test func liveAcceptsEventStream() async throws {
        let transport = CrewRequestRecorder(contentType: "text/event-stream", reply: ": ping\n\n")

        _ = try await service(transport).live(crew)

        let seen = try #require(transport.last)
        #expect(seen.accept?.contains("text/event-stream") == true)
        #expect(seen.path.hasSuffix("/crews/\(crew)/live"))
    }

    @Test func pinsUnwrapTheList() async throws {
        let transport = CrewRequestRecorder(reply: #"{"messages":[{"id":"\#(message)"}]}"#)

        let pins = try await service(transport).pins(crew, channel: channel)

        #expect(pins.map(\.id) == [message])
    }

    @Test func clearingTheMuteSendsNoDate() async throws {
        let transport = CrewRequestRecorder(status: .noContent)

        try await service(transport).setNotify(crew, notify: "all", mutedUntil: nil)

        let seen = try #require(transport.last)
        #expect(seen.method == .put)
        let json = try #require(JSONSerialization.jsonObject(with: Data(seen.body.utf8)) as? [String: Any])
        #expect(json["notify"] as? String == "all")
        #expect(json["mutedUntil"] == nil)
    }

    @Test func termsAreAcceptedWhenTheServerSaysSo() async throws {
        let transport = CrewRequestRecorder(reply: #"{"version":2,"accepted":true}"#)

        #expect(try await service(transport).termsAccepted())
    }
}
