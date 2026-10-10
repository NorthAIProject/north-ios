import Foundation
import NorthAPI
import Testing
@testable import khepri

/// Locking the phone or switching apps mid-reply cuts the connection, but the
/// server finishes the reply (and any approved tools) and stores it. The
/// conversation collects it rather than showing an error.
@MainActor
struct ConversationRecoveryTests {
    /// Locking the phone mid-reply cuts the stream, but the server finishes
    /// and stores the reply. The app fetches it instead of showing an error.
    @Test func anInterruptedReplyIsCollectedFromTheServer() async throws {
        let coach = FakeCoach(reply: [.token("Hands ")])
        coach.replyFailure = APIError.network("The network connection was lost.", code: .networkConnectionLost)
        let question = Self.message("u1", .user, "How do I do a push-up?")
        coach.details = [
            Self.detail([]),
            Self.detail([question]),
            Self.detail([question, Self.message("r1", .coach, "Hands under shoulders.")])
        ]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()

        store.send("How do I do a push-up?")
        try await waitUntil { !store.isAwaitingReply && coach.fetches == 3 }

        #expect(store.replyError == nil, "a cut connection is not the coach failing")
        #expect(store.messages.map(\.text) == ["How do I do a push-up?", "Hands under shoulders."])
        #expect(store.messages.last?.id == "r1" && store.messages.last?.isStored == true)
        #expect(store.canSend)
    }

    /// Cut off while in the background: nothing to fetch until the person is
    /// back, and the screen says the coach is still on it.
    @Test func aReplyCutInTheBackgroundIsCollectedOnReturn() async throws {
        let background = BackgroundFlag(true)
        let coach = FakeCoach(reply: [])
        coach.replyFailure = URLError(.networkConnectionLost)
        let question = Self.message("u1", .user, "Plan my week")
        coach.details = [Self.detail([]), Self.detail([question, Self.message("r1", .coach, "Here it is.")])]
        let store = ConversationStore(
            conversationID: "c1", title: "", coach: coach, recovery: .immediate(isInBackground: { background.value })
        )
        await store.load()

        store.send("Plan my week")
        try await waitUntilReady(store)
        #expect(store.isAwaitingReply)
        #expect(store.replyError == nil)
        #expect(!store.canSend, "the reply is still owed")
        #expect(CoachActivity.resolve(store, flash: nil, isListening: false).status == "is still thinking")
        #expect(coach.fetches == 1)

        background.value = false
        await store.recoverIfNeeded()
        #expect(!store.isAwaitingReply)
        #expect(store.messages.last?.text == "Here it is.")
    }

    /// iOS cancelling the request is an interruption too; the person pressing
    /// Stop is not.
    @Test func aSystemCancelledReplyIsCollected() async throws {
        let coach = FakeCoach(reply: [])
        coach.replyFailure = APIError.network("cancelled", code: .cancelled)
        let question = Self.message("u1", .user, "Hi")
        coach.details = [Self.detail([]), Self.detail([question, Self.message("r1", .coach, "Hello.")])]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()

        store.send("Hi")
        try await waitUntil { store.messages.last?.text == "Hello." }
        #expect(store.replyError == nil)
    }

    @Test func aReplyStillNotThereAfterAWhileSaysSoGently() async throws {
        let coach = FakeCoach(reply: [])
        coach.replyFailure = URLError(.timedOut)
        let question = Self.message("u1", .user, "Hi")
        coach.details = [Self.detail([]), Self.detail([question])]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()

        store.send("Hi")
        try await waitUntil { store.replyNote != nil }

        #expect(store.replyNote == "Your coach's reply will appear here when it's ready — pull to refresh.")
        #expect(store.replyError == nil)
        #expect(!store.isAwaitingReply)
        #expect(store.canSend)
        #expect(coach.fetches == 1 + ReplyRecovery.immediate.attempts)
    }

    @Test func pullingToRefreshAfterGivingUpShowsTheReply() async throws {
        let coach = FakeCoach(reply: [])
        coach.replyFailure = URLError(.timedOut)
        let question = Self.message("u1", .user, "Hi")
        let answered = Self.detail([question, Self.message("r1", .coach, "Hello.")])
        let unanswered = Self.detail([question])
        coach.details = [Self.detail([]), unanswered, unanswered, unanswered, answered]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()
        store.send("Hi")
        try await waitUntil { store.replyNote != nil }

        await store.refresh()

        #expect(store.replyNote == nil)
        #expect(store.messages.last?.text == "Hello.")
    }

    /// Cut off after an approval: the server holds the tools' results and the
    /// reply is owed, so the existing resume path collects it.
    @Test func anInterruptedReplyThatAwaitsResumeIsResumed() async throws {
        let coach = FakeCoach(reply: [], resume: [.token("Logged."), .done(messageID: "r2")])
        coach.replyFailure = URLError(.networkConnectionLost)
        let question = Self.message("u1", .user, "Log my check-in")
        coach.details = [Self.detail([]), Self.detail([question], awaitingResume: true)]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()

        store.send("Log my check-in")
        try await waitUntil { store.messages.last?.id == "r2" && store.phase == .ready }
        #expect(store.messages.last?.text == "Logged.")
        #expect(coach.resumes == 1)
    }

    /// The approved tools run on the server whether the app hears back or
    /// not. Cut off, the app waits for them, then collects the reply.
    @Test func anInterruptedAllowWaitsForTheToolsThenResumes() async throws {
        let approval = Self.planApproval
        let coach = FakeCoach(
            reply: [.approval(approval), .done(messageID: nil)],
            resume: [.token("Your plan is ready."), .done(messageID: "r2")]
        )
        coach.decideError = APIError.network("The network connection was lost.", code: .networkConnectionLost)
        let question = Self.message("u1", .user, "Make me a plan")
        coach.details = [
            Self.detail([]),
            Self.detail([question], approval: approval),
            Self.detail([question], awaitingResume: true)
        ]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()
        store.send("Make me a plan")
        try await waitUntilReady(store)

        await store.decide(approve: true)
        try await waitUntil { store.messages.last?.id == "r2" && store.phase == .ready }

        #expect(coach.decisions == [true], "never sent twice")
        #expect(store.replyError == nil)
        #expect(store.pendingApproval == nil)
        #expect(store.messages.last?.text == "Your plan is ready.")
    }

    /// A second Allow while the first is still running answers 409: the
    /// tools are under way, so wait for them rather than call it a failure.
    @Test func allowingWhileTheToolsRunIsNotAnError() async throws {
        let approval = Self.planApproval
        let coach = FakeCoach(
            reply: [.approval(approval), .done(messageID: nil)],
            resume: [.token("Done."), .done(messageID: "r2")]
        )
        coach.decideError = APIError.conflict("this approval is already being resolved")
        let question = Self.message("u1", .user, "Make me a plan")
        coach.details = [Self.detail([]), Self.detail([question], awaitingResume: true)]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()
        store.send("Make me a plan")
        try await waitUntilReady(store)

        await store.decide(approve: true)
        try await waitUntil { store.messages.last?.id == "r2" && store.phase == .ready }
        #expect(store.replyError == nil)
        #expect(store.messages.last?.text == "Done.")
    }

    /// Opening a conversation whose last word is the person's, sent moments
    /// ago, means the reply is still being written: wait for it.
    @Test func openingAConversationWithAReplyOnItsWayWaitsForIt() async throws {
        let question = Self.message("u1", .user, "Hi", at: .now.addingTimeInterval(-20))
        let coach = FakeCoach()
        coach.details = [Self.detail([question]), Self.detail([question, Self.message("r1", .coach, "Hello.")])]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)

        await store.load()

        #expect(store.messages.last?.text == "Hello.")
        #expect(!store.isAwaitingReply)
    }

    /// A question left unanswered long ago is history, not a reply on its way.
    @Test func anOldUnansweredQuestionIsNotWaitedOn() async {
        let question = Self.message("u1", .user, "Hi", at: .now.addingTimeInterval(-3600))
        let coach = FakeCoach()
        coach.details = [Self.detail([question])]
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)

        await store.load()

        #expect(coach.fetches == 1)
        #expect(!store.isAwaitingReply && store.replyNote == nil)
        #expect(store.canSend)
    }

    @Test func aReplyStoppedByThePersonIsNotRecovered() async throws {
        let coach = FakeCoach(reply: [.token("Hands ")])
        coach.replyDelay = .seconds(5)
        coach.replyFailure = URLError(.cancelled)
        let store = ConversationStore(conversationID: "c1", title: "", coach: coach, recovery: .immediate)
        await store.load()

        store.send("How do I do a push-up?")
        store.stop()
        try await waitUntilReady(store)
        #expect(!store.isAwaitingReply)
        #expect(coach.fetches == 1)
        #expect(store.messages.last?.text == "Hands ", "what arrived stays")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    static let planApproval = ToolApproval(
        messageId: "m9", calls: [.init(name: "create_workout_plan", summary: "Create a 4-day plan")]
    )

    static func message(
        _ id: String, _ role: ChatMessage.RolePayload, _ text: String, at date: Date = .now
    ) -> ChatMessage {
        ChatMessage(id: id, role: role, text: text, attachments: [], exercises: [], createdAt: date)
    }

    static func detail(
        _ messages: [ChatMessage], approval: ToolApproval? = nil, awaitingResume: Bool = false
    ) -> ConversationDetail {
        ConversationDetail(
            conversation: .init(id: "c1", title: "Test", kind: .chat, ended: false, updatedAt: .now),
            messages: messages,
            pendingApproval: approval,
            awaitingResume: awaitingResume
        )
    }

    private func waitUntilReady(_ store: ConversationStore) async throws {
        try await waitUntil { store.phase == .ready }
    }
}

/// Whether the app is in the background, flipped by a test.
final class BackgroundFlag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

extension ReplyRecovery {
    /// Polls without waiting, a few times, in the foreground.
    static let immediate = ReplyRecovery(pollInterval: .milliseconds(1), attempts: 3, isInBackground: { false })

    static func immediate(isInBackground: @escaping @MainActor () -> Bool) -> ReplyRecovery {
        ReplyRecovery(pollInterval: .milliseconds(1), attempts: 3, isInBackground: isInBackground)
    }
}
