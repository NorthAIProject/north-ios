import Foundation
import NorthAPI
import OpenAPIRuntime

/// What the crew's live stream tells the app. Every event is a signal, never
/// content: the consumer refetches what the event points at.
nonisolated enum CrewLiveEvent: Equatable, Sendable {
    /// First connect and every reconnect. Nothing is replayed, so treat it as a resync.
    case connected
    case message(channelID: String, seq: Int64)
    case update(messageID: String)
    case channels
    /// An empty `userID` means the server refused the stream (removed or gone).
    case removed(userID: String)
    case resync
}

/// Turns the crew's Server-Sent Events into typed events and keeps the
/// connection alive, reconnecting with backoff.
nonisolated struct CrewLiveStream: Sendable {
    let crewID: String
    let service: CrewChatServicing
    let backoff: [Duration]

    init(crewID: String, service: CrewChatServicing, backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10)]) {
        self.crewID = crewID
        self.service = service
        self.backoff = backoff
    }

    /// Ends when the consuming task is cancelled, or when the server refuses the stream.
    func events() -> AsyncStream<CrewLiveEvent> {
        AsyncStream { continuation in
            let task = Task {
                await run(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<CrewLiveEvent>.Continuation) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                let body = try await service.live(crewID)
                attempt = 0
                continuation.yield(.connected)
                for try await frame in body.asDecodedServerSentEvents() {
                    if let event = Self.decode(frame) { continuation.yield(event) }
                }
            } catch let error as APIError {
                switch error {
                case .notFound, .refused:
                    continuation.yield(.removed(userID: ""))
                    return
                default:
                    break
                }
            } catch {
                // Dropped connection: fall through to the backoff and reopen.
            }
            guard !Task.isCancelled else { return }
            let wait = backoff.isEmpty ? Duration.zero : backoff[min(attempt, backoff.count - 1)]
            attempt += 1
            try? await Task.sleep(for: wait)
            await Task.yield()
        }
    }

    private struct Payload: Decodable {
        var type: String
        var channelId: String?
        var messageId: String?
        var userId: String?
        var seq: Int64?
    }

    /// Unknown types, pings (comment-only frames) and bad JSON are nil, so a
    /// server that adds a type does not break older builds.
    static func decode(_ frame: ServerSentEvent) -> CrewLiveEvent? {
        guard let data = frame.data, let payload = try? JSONDecoder().decode(Payload.self, from: Data(data.utf8)) else { return nil }
        switch payload.type {
        case "message":
            guard let channel = payload.channelId, let seq = payload.seq else { return nil }
            return .message(channelID: channel, seq: seq)
        case "update":
            guard let id = payload.messageId else { return nil }
            return .update(messageID: id)
        case "channels": return .channels
        case "removed": return .removed(userID: payload.userId ?? "")
        case "resync": return .resync
        default: return nil
        }
    }
}
