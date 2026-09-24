import Foundation
import NorthAPI
import OpenAPIRuntime

/// What arrives while the coach replies. Mirrors the server's event frames.
enum CoachEvent: Sendable, Equatable {
    case token(String)
    case exercises([String])
    case approval(ToolApproval)
    case failed(String)
    /// Always last. The stored reply's id, or nil when the turn stopped to ask.
    case done(messageID: String?)
}

/// The coach, over the generated client. Stateless: the stores hold state.
protocol CoachServicing: Sendable {
    func conversations() async throws -> [ConversationSummary]
    func start(reflection: Bool) async throws -> ConversationSummary
    func conversation(_ id: String) async throws -> ConversationDetail
    func delete(_ id: String) async throws
    func reply(in id: String, text: String) -> AsyncThrowingStream<CoachEvent, Error>
    func resume(_ id: String) -> AsyncThrowingStream<CoachEvent, Error>
    func decide(in id: String, messageID: String, approve: Bool) async throws
    func rate(in id: String, messageID: String, helpful: Bool?) async throws -> ChatMessage
    func exercise(_ slug: String) async throws -> ExerciseDetail
}

struct CoachService: CoachServicing {
    var api: Client = API.shared
    var exercises = ExerciseCache.shared

    func conversations() async throws -> [ConversationSummary] {
        try await NorthAPI.call { try await api.listConversations().ok.body.json.conversations }
    }

    func start(reflection: Bool) async throws -> ConversationSummary {
        try await NorthAPI.call {
            try await api.startConversation(body: .json(.init(kind: reflection ? .reflection : .chat))).created.body.json
        }
    }

    func conversation(_ id: String) async throws -> ConversationDetail {
        try await NorthAPI.call { try await api.getConversation(path: .init(id: id)).ok.body.json }
    }

    func delete(_ id: String) async throws {
        _ = try await NorthAPI.call { try await api.deleteConversation(path: .init(id: id)).noContent }
    }

    func reply(in id: String, text: String) -> AsyncThrowingStream<CoachEvent, Error> {
        events {
            try await api.replyInConversation(path: .init(id: id), body: .json(.init(text: text))).ok.body.textEventStream
        }
    }

    func resume(_ id: String) -> AsyncThrowingStream<CoachEvent, Error> {
        events { try await api.resumeConversation(path: .init(id: id)).ok.body.textEventStream }
    }

    func decide(in id: String, messageID: String, approve: Bool) async throws {
        _ = try await NorthAPI.call {
            try await api.decideToolCalls(path: .init(id: id, messageID: messageID), body: .json(.init(approve: approve))).noContent
        }
    }

    func rate(in id: String, messageID: String, helpful: Bool?) async throws -> ChatMessage {
        try await NorthAPI.call {
            try await api.rateMessage(path: .init(id: id, messageID: messageID), body: .json(.init(helpful: helpful))).ok.body.json
        }
    }

    func exercise(_ slug: String) async throws -> ExerciseDetail {
        try await exercises.detail(slug) { slug in
            try await NorthAPI.call { try await api.getExercise(path: .init(slug: slug)).ok.body.json }
        }
    }

    /// Opens the stream, then decodes each Server-Sent Event by its name.
    /// Cancelling the consuming task cancels the request.
    private func events(_ open: @escaping @Sendable () async throws -> HTTPBody) -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try await NorthAPI.call(open)
                    for try await frame in body.asDecodedServerSentEvents() {
                        if let event = try Self.decode(frame) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Unknown event names are skipped, so a server that adds one does not
    /// break older builds of the app.
    static func decode(_ frame: ServerSentEvent) throws -> CoachEvent? {
        let data = Data((frame.data ?? "").utf8)
        let decoder = JSONDecoder()
        switch frame.event {
        case "token":
            return .token(try decoder.decode(Components.Schemas.ReplyTokenEvent.self, from: data).text)
        case "exercises":
            return .exercises(try decoder.decode(Components.Schemas.ReplyExercisesEvent.self, from: data).slugs)
        case "approval":
            return .approval(try decoder.decode(ToolApproval.self, from: data))
        case "error":
            return .failed(try decoder.decode(Components.Schemas.ReplyErrorEvent.self, from: data).message)
        case "done":
            return .done(messageID: try decoder.decode(Components.Schemas.ReplyDoneEvent.self, from: data).messageId)
        default:
            return nil
        }
    }
}

/// Exercise details don't change during a session, and a reply often shows
/// the same card twice, so each slug is fetched once.
actor ExerciseCache {
    /// One cache for the app: cards, thumbnails and sheets all ask for the
    /// same few exercises.
    static let shared = ExerciseCache()

    private var details: [String: ExerciseDetail] = [:]
    private var inFlight: [String: Task<ExerciseDetail, Error>] = [:]

    func detail(_ slug: String, fetch: @escaping @Sendable (String) async throws -> ExerciseDetail) async throws -> ExerciseDetail {
        if let cached = details[slug] { return cached }
        if let running = inFlight[slug] { return try await running.value }
        let task = Task { try await fetch(slug) }
        inFlight[slug] = task
        defer { inFlight[slug] = nil }
        let detail = try await task.value
        details[slug] = detail
        return detail
    }
}
