import Foundation
import NorthAPI
import OpenAPIRuntime
import Testing
@testable import khepri

@MainActor
struct ConversationStoreTests {
    @Test func aReplyStreamsIntoOneMessageThatBecomesTheStoredOne() async throws {
        let coach = FakeCoach(reply: [.token("Hands under "), .token("shoulders."), .exercises(["push-up"]), .done(messageID: "stored-1")])
        let store = ConversationStore(conversationID: "c1", title: "Push-ups", coach: coach)
        await store.load()

        store.send("How do I do a push-up?")
        try await waitUntilReady(store)

        #expect(store.messages.map(\.role) == [.user, .coach])
        let reply = try #require(store.messages.last)
        #expect(reply.text == "Hands under shoulders.")
        #expect(reply.exercises == ["push-up"])
        #expect(reply.id == "stored-1")
        #expect(reply.isStored && !reply.isStreaming)
        #expect(coach.sent == ["How do I do a push-up?"])
    }

    @Test func aTurnThatStopsToAskLeavesNoEmptyBubble() async throws {
        let approval = ToolApproval(messageId: "m9", calls: [.init(name: "log_check_in", summary: "Log today's check-in: mood 4, energy 3")])
        let coach = FakeCoach(reply: [.approval(approval), .done(messageID: nil)], resume: [.token("Logged."), .done(messageID: "stored-2")])
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach)
        await store.load()

        store.send("Log my check-in")
        try await waitUntilReady(store)
        #expect(store.messages.map(\.role) == [.user])
        #expect(store.pendingApproval == approval)
        #expect(!store.canSend, "the coach is waiting on an answer")

        await store.decide(approve: true)
        try await waitUntilReady(store)
        #expect(coach.decisions == [true])
        #expect(store.pendingApproval == nil)
        #expect(store.messages.last?.text == "Logged.")
    }

    @Test func aFailedReplyShowsItsReasonAndKeepsTheQuestion() async throws {
        let coach = FakeCoach(reply: [.failed("The coach is busy right now."), .done(messageID: nil)])
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach)
        await store.load()

        store.send("Hello")
        try await waitUntilReady(store)

        #expect(store.messages.map(\.text) == ["Hello"])
        #expect(store.replyError == "The coach is busy right now.")
    }

    @Test func ratingTheSameWayTwiceClearsIt() async throws {
        let coach = FakeCoach(history: [ChatMessage(id: "r1", role: .coach, text: "Try this.", attachments: [], exercises: [], createdAt: .now)])
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach)
        await store.load()
        let reply = try #require(store.messages.first)

        await store.rate(reply, helpful: true)
        #expect(store.messages.first?.helpful == true)
        await store.rate(try #require(store.messages.first), helpful: true)
        #expect(store.messages.first?.helpful == nil)
        #expect(coach.ratings == [true, nil])
    }

    private func waitUntilReady(_ store: ConversationStore) async throws {
        for _ in 0..<200 where store.phase != .ready {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.phase == .ready)
    }
}

/// The header's ring and status line, as Loci's Muse chat has them.
@MainActor
struct CoachActivityTests {
    @Test func eachStateHasItsMoodAndStatus() {
        #expect(CoachActivity.resolve(phase: .ready) == .ready)
        #expect(CoachActivity.resolve(phase: .loading) == CoachActivity(mood: .working, status: "is catching up"))
        #expect(CoachActivity.resolve(phase: .replying) == CoachActivity(mood: .working, status: "is thinking"))
        #expect(CoachActivity.resolve(phase: .replying, hasReplyText: true) == CoachActivity(mood: .working, status: "is writing"))
        #expect(CoachActivity.resolve(phase: .ready, awaitingApproval: true) == CoachActivity(mood: .idle, status: "needs your OK"))
        #expect(CoachActivity.resolve(phase: .ready, flash: .done) == CoachActivity(mood: .celebrating, status: "is done"))
        #expect(CoachActivity.resolve(phase: .ready, isListening: true) == CoachActivity(mood: .listening, status: "is listening"))
        #expect(CoachActivity.resolve(phase: .ready, replyFailed: true) == CoachActivity(mood: .idle, status: "hit a snag"))
        #expect(CoachActivity.resolve(phase: .failed("offline")) == CoachActivity(mood: .idle, status: "hit a snag"))
        #expect(CoachActivity.resolve(phase: .ready, ended: true) == CoachActivity(mood: .idle, status: "finished this reflection"))
    }

    @Test func aReplyBeingWrittenOutranksEverythingElse() {
        let activity = CoachActivity.resolve(phase: .replying, awaitingApproval: true, replyFailed: true, flash: .done, isListening: true)
        #expect(activity.status == "is thinking")
        #expect(CoachActivity.resolve(phase: .ready, awaitingApproval: true, isListening: true).status == "needs your OK")
        #expect(CoachActivity.resolve(phase: .ready, replyFailed: true, isListening: true).mood == .listening)
    }

    @Test func onlyAReplyThatFinishesByItselfEarnsDone() {
        #expect(CoachActivity.flash(from: .replying, to: .ready, replyFailed: false, awaitingApproval: false, stopped: false) == .done)
        #expect(CoachActivity.flash(from: .replying, to: .ready, replyFailed: true, awaitingApproval: false, stopped: false) == nil)
        #expect(CoachActivity.flash(from: .replying, to: .ready, replyFailed: false, awaitingApproval: true, stopped: false) == nil)
        #expect(CoachActivity.flash(from: .replying, to: .ready, replyFailed: false, awaitingApproval: false, stopped: true) == nil)
        #expect(CoachActivity.flash(from: .loading, to: .ready, replyFailed: false, awaitingApproval: false, stopped: false) == nil)
    }

    @Test func theStoreDrivesTheHeaderFromThinkingToWriting() async throws {
        let coach = FakeCoach(reply: [.token("Hands under "), .done(messageID: "stored-1")])
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach)
        #expect(CoachActivity.resolve(store, flash: nil, isListening: false).status == "is catching up")
        await store.load()
        #expect(CoachActivity.resolve(store, flash: nil, isListening: false) == .ready)

        store.send("How do I do a push-up?")
        #expect(CoachActivity.resolve(store, flash: nil, isListening: false).status == "is thinking")
        for _ in 0..<200 where store.phase != .ready {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(CoachActivity.resolve(store, flash: nil, isListening: false) == .ready)
    }
}

struct CoachEventDecodingTests {
    @Test func decodesEachFrameByName() throws {
        #expect(try CoachService.decode(ServerSentEvent(event: "token", data: #"{"text":"Hi"}"#)) == .token("Hi"))
        #expect(try CoachService.decode(ServerSentEvent(event: "exercises", data: #"{"slugs":["push-up"]}"#)) == .exercises(["push-up"]))
        #expect(try CoachService.decode(ServerSentEvent(event: "done", data: "{}")) == .done(messageID: nil))
    }

    @Test func skipsEventsItDoesNotKnow() throws {
        #expect(try CoachService.decode(ServerSentEvent(event: "future-feature", data: "{}")) == nil)
    }
}

// MARK: - Fake

final class FakeCoach: CoachServicing, @unchecked Sendable {
    private let history: [ChatMessage]
    private let replyEvents: [CoachEvent]
    private let resumeEvents: [CoachEvent]
    private(set) var sent: [String] = []
    private(set) var decisions: [Bool] = []
    private(set) var ratings: [Bool?] = []

    init(history: [ChatMessage] = [], reply: [CoachEvent] = [], resume: [CoachEvent] = []) {
        self.history = history
        self.replyEvents = reply
        self.resumeEvents = resume
    }

    func conversation(_ id: String) async throws -> ConversationDetail {
        ConversationDetail(
            conversation: .init(id: id, title: "Test", kind: .chat, ended: false, updatedAt: .now),
            messages: history,
            awaitingResume: false
        )
    }

    func reply(in id: String, text: String) -> AsyncThrowingStream<CoachEvent, Error> {
        sent.append(text)
        return Self.stream(replyEvents)
    }

    func resume(_ id: String) -> AsyncThrowingStream<CoachEvent, Error> { Self.stream(resumeEvents) }

    func decide(in id: String, messageID: String, approve: Bool) async throws { decisions.append(approve) }

    func rate(in id: String, messageID: String, helpful: Bool?) async throws -> ChatMessage {
        ratings.append(helpful)
        return history[0]
    }

    func conversations() async throws -> [ConversationSummary] { [] }
    func start(reflection: Bool) async throws -> ConversationSummary { throw APIError.invalidResponse }
    func delete(_ id: String) async throws {}
    func exercise(_ slug: String) async throws -> ExerciseDetail { throw APIError.invalidResponse }

    private static func stream(_ events: [CoachEvent]) -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}
