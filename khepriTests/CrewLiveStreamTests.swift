import Foundation
import Synchronization
import NorthAPI
import OpenAPIRuntime
import Testing
@testable import khepri

/// Hands out scripted bodies in order; every method but `live` is unused.
final class LiveScriptService: CrewChatServicing, Sendable {
    private let bodies: Mutex<[Result<HTTPBody, APIError>]>
    init(_ bodies: [Result<HTTPBody, APIError>]) { self.bodies = Mutex(bodies) }

    func live(_ crewID: String) async throws -> HTTPBody {
        let next = bodies.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        switch next {
        case .success(let body): return body
        case .failure(let error): throw error
        case nil: return Self.blocking()
        }
    }

    /// A body that never produces a frame and never ends.
    static func blocking() -> HTTPBody {
        HTTPBody(AsyncStream<ArraySlice<UInt8>> { _ in }, length: .unknown)
    }

    func space(_ crewID: String) async throws -> CrewSpace { fatalError() }
    func messages(_ crewID: String, channel: String, before: Int64?, after: Int64?) async throws -> Components.Schemas.CrewMessagePage { fatalError() }
    func message(_ crewID: String, id: String) async throws -> CrewMessage { fatalError() }
    func send(_ crewID: String, channel: String, body: String, replyTo: String?, clientID: UUID) async throws -> CrewMessage { fatalError() }
    func edit(_ crewID: String, id: String, body: String) async throws -> CrewMessage { fatalError() }
    func delete(_ crewID: String, id: String) async throws { fatalError() }
    func react(_ crewID: String, id: String, emoji: String, on: Bool) async throws { fatalError() }
    func pin(_ crewID: String, id: String, on: Bool) async throws { fatalError() }
    func pins(_ crewID: String, channel: String) async throws -> [CrewMessage] { fatalError() }
    func markRead(_ crewID: String, channel: String, seq: Int64) async throws { fatalError() }
    func report(_ crewID: String, id: String, reason: String, note: String?) async throws { fatalError() }
    func setNotify(_ crewID: String, notify: String, mutedUntil: Date?) async throws { fatalError() }
    func unread() async throws -> Components.Schemas.CrewUnreadList { fatalError() }
    func termsAccepted() async throws -> Bool { fatalError() }
    func acceptTerms() async throws { fatalError() }
    func block(_ userID: String) async throws { fatalError() }
}

nonisolated struct CrewLiveStreamTests {
    private func frame(_ type: String, _ fields: String = "") -> ServerSentEvent {
        ServerSentEvent(event: type, data: #"{"type":"\#(type)","crewId":"c1"\#(fields)}"#)
    }

    @Test func decodesKnownFrames() {
        #expect(CrewLiveStream.decode(frame("message", #","channelId":"ch1","seq":7"#)) == .message(channelID: "ch1", seq: 7))
        #expect(CrewLiveStream.decode(frame("update", #","messageId":"m1""#)) == .update(messageID: "m1"))
        #expect(CrewLiveStream.decode(frame("channels")) == .channels)
        #expect(CrewLiveStream.decode(frame("removed", #","userId":"u1""#)) == .removed(userID: "u1"))
        #expect(CrewLiveStream.decode(frame("resync")) == .resync)
    }

    @Test func ignoresUnknownAndPings() {
        #expect(CrewLiveStream.decode(frame("poll")) == nil)
        #expect(CrewLiveStream.decode(ServerSentEvent()) == nil)
        #expect(CrewLiveStream.decode(ServerSentEvent(event: "message", data: "not json")) == nil)
        #expect(CrewLiveStream.decode(frame("message")) == nil, "a message without a channel or seq points at nothing")
    }

    @Test(.timeLimit(.minutes(1)))
    func reconnectEmitsConnectedAgain() async {
        let first = HTTPBody(#"event: message\#ndata: {"type":"message","crewId":"c1","channelId":"ch1","seq":3}\#n\#n"#)
        let service = LiveScriptService([.success(first), .success(LiveScriptService.blocking())])
        let stream = CrewLiveStream(crewID: "c1", service: service, backoff: [.zero])
        var seen: [CrewLiveEvent] = []
        for await event in stream.events() {
            seen.append(event)
            if seen.count == 3 { break }
        }
        #expect(seen == [.connected, .message(channelID: "ch1", seq: 3), .connected])
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedStreamEndsAsRemoved() async {
        let service = LiveScriptService([.failure(.notFound(nil))])
        var seen: [CrewLiveEvent] = []
        for await event in CrewLiveStream(crewID: "c1", service: service, backoff: [.zero]).events() { seen.append(event) }
        #expect(seen == [.removed(userID: "")])
    }
}
