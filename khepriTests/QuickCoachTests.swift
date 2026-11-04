import Foundation
import NorthAPI
import Testing
@testable import khepri

struct ReplySentencesTests {
    @Test func holdsBackTheSentenceStillArriving() {
        var sentences = ReplySentences()
        #expect(sentences.take(from: "Rest two", finished: false).isEmpty)
        #expect(sentences.take(from: "Rest two days. Then", finished: false) == ["Rest two days."])
        #expect(sentences.take(from: "Rest two days. Then train.", finished: true) == ["Then train."])
    }

    @Test func neverReadsASentenceTwice() {
        var sentences = ReplySentences()
        _ = sentences.take(from: "One here. Two here. Three", finished: false)
        #expect(sentences.take(from: "One here. Two here. Three", finished: false).isEmpty)
    }

    @Test func aDecimalDoesNotEndASentence() {
        var sentences = ReplySentences()
        #expect(sentences.take(from: "Eat 2.5 g per kilo today.", finished: true) == ["Eat 2.5 g per kilo today."])
    }

    @Test func marksAreNotRead() {
        #expect(ReplySentences.readable("**Protein** comes first.") == "Protein comes first.")
        #expect(ReplySentences.readable("- Eggs at breakfast") == "Eggs at breakfast")
        #expect(ReplySentences.readable("1. Warm up") == "Warm up")
        #expect(ReplySentences.readable("## Plan") == "Plan")
        #expect(ReplySentences.readable("---") == nil)
    }
}

@MainActor
struct QuickCoachSessionTests {
    private let reply: [CoachEvent] = [.token("Rest two days. "), .token("Then train."), .done(messageID: "stored")]

    @Test func letGoSendsWhatWasHeardInOneNewChat() async throws {
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach, hears: "How much rest")

        session.holdBegan()
        #expect(session.mode == .listening)
        try await untilHearing(session)
        await session.holdEnded()
        try await untilReplied(session)

        #expect(session.mode == .open)
        #expect(coach.started == 1)
        #expect(coach.sent == ["How much rest"])
        #expect(session.draft.isEmpty)
        #expect(session.store?.messages.last?.text == "Rest two days. Then train.")
        #expect(session.conversation?.id == "c1")
    }

    @Test func aReplyToSpeechIsReadAloudSentenceBySentence() async throws {
        let speaker = FakeSpeaker()
        let session = await makeSession(coach: FakeCoach(reply: reply), hears: "How much rest", speaker: speaker)

        session.holdBegan()
        try await untilHearing(session)
        await session.holdEnded()
        try await untilReplied(session)

        #expect(speaker.spoken == ["Rest two days.", "Then train."])
    }

    @Test func aTypedQuestionIsNotReadAloud() async throws {
        let speaker = FakeSpeaker()
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach, speaker: speaker)

        session.openForTyping()
        session.draft = "How much protein"
        await session.send()
        try await untilReplied(session)

        #expect(coach.sent == ["How much protein"])
        #expect(speaker.spoken.isEmpty)
    }

    @Test func dictatingInTheComposerCountsAsSpeaking() async throws {
        let speaker = FakeSpeaker()
        let session = await makeSession(coach: FakeCoach(reply: reply), speaker: speaker)

        session.openForTyping()
        session.composerStartedListening()
        session.draft = "How much protein"
        await session.send()
        try await untilReplied(session)

        #expect(speaker.spoken == ["Rest two days.", "Then train."])
    }

    @Test func mutingSilencesTheReplyAndIsRemembered() async throws {
        let speaker = FakeSpeaker()
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let session = await makeSession(coach: FakeCoach(reply: reply), hears: "How much rest", speaker: speaker, defaults: defaults)

        session.isMuted = true
        #expect(speaker.stops == 1)
        session.holdBegan()
        try await untilHearing(session)
        await session.holdEnded()
        try await untilReplied(session)

        #expect(speaker.spoken.isEmpty)
        let next = await makeSession(coach: FakeCoach(), defaults: defaults)
        #expect(next.isMuted)
    }

    @Test func aFollowUpStaysInTheSameChat() async throws {
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach)

        session.openForTyping()
        session.draft = "First"
        await session.send()
        try await untilReplied(session)
        session.draft = "Second"
        await session.send()
        try await until { coach.sent.count == 2 }
        try await untilReplied(session)

        #expect(coach.started == 1)
        #expect(coach.sent == ["First", "Second"])
    }

    @Test func aFollowUpTypedAfterSpeakingIsNotReadAloud() async throws {
        let speaker = FakeSpeaker()
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach, hears: "Spoken", speaker: speaker)

        session.holdBegan()
        try await untilHearing(session)
        await session.holdEnded()
        try await untilReplied(session)
        speaker.spoken = []

        session.draft = "Typed"
        await session.send()
        try await until { coach.sent.count == 2 }
        try await untilReplied(session)

        #expect(speaker.spoken.isEmpty)
    }

    @Test func lettingGoWithoutAWordMakesNoChatAndStaysOpen() async throws {
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach, hears: nil)

        session.holdBegan()
        try await untilHearing(session)
        await session.holdEnded()

        #expect(session.mode == .open)
        #expect(session.heardNothing)
        #expect(session.wantsKeyboard)
        #expect(coach.started == 0)
        #expect(coach.sent.isEmpty)
    }

    @Test func lettingGoWhileStillGettingReadySendsNothing() async throws {
        let coach = FakeCoach(reply: reply)
        let transcriber = HeldTranscriber(hears: "Too early", startsAfter: .milliseconds(200))
        let session = await makeSession(coach: coach, transcriber: transcriber)

        session.holdBegan()
        #expect(!session.isHearing)
        await session.holdEnded()

        #expect(session.mode == .open)
        #expect(session.heardNothing)
        #expect(coach.started == 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(session.draft.isEmpty, "the late start must not write into the field")
        #expect(await transcriber.stops >= 1, "the late start must close the microphone")
    }

    @Test func closingWithoutSendingMakesNoChat() async throws {
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach)

        session.openForTyping()
        session.draft = "Never mind"
        session.close()

        #expect(session.mode == .closed)
        #expect(session.draft.isEmpty)
        #expect(coach.started == 0)
    }

    @Test func closingStopsTheReading() async throws {
        let speaker = FakeSpeaker()
        let session = await makeSession(coach: FakeCoach(reply: reply), hears: "Spoken", speaker: speaker)

        session.holdBegan()
        try await untilHearing(session)
        await session.holdEnded()
        try await untilReplied(session)
        let before = speaker.stops
        session.close()

        #expect(speaker.stops == before + 1)
        #expect(session.store == nil)
        #expect(session.conversation == nil)
    }

    @Test func aNewVisitIsANewChat() async throws {
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach)

        session.openForTyping()
        session.draft = "First"
        await session.send()
        try await untilReplied(session)
        session.close()

        session.openForTyping()
        session.draft = "Second"
        await session.send()
        try await until { coach.sent.count == 2 }

        #expect(coach.started == 2)
    }

    @Test func aFailedStartKeepsTheWords() async throws {
        let coach = FakeCoach(reply: reply)
        coach.startError = APIError.invalidResponse
        let session = await makeSession(coach: coach)

        session.openForTyping()
        session.draft = "Keep me"
        await session.send()

        #expect(session.draft == "Keep me")
        #expect(session.notice != nil)
        #expect(session.store == nil)
        #expect(coach.sent.isEmpty)

        coach.startError = nil
        await session.send()
        try await untilReplied(session)
        #expect(coach.sent == ["Keep me"])
        #expect(session.notice == nil)
    }

    @Test func aSecondSendWhileTheFirstIsStartingSendsOnce() async throws {
        let coach = FakeCoach(reply: reply)
        let session = await makeSession(coach: coach)

        session.openForTyping()
        session.draft = "Once"
        async let first: Void = session.send()
        async let second: Void = session.send()
        _ = await (first, second)
        try await untilReplied(session)

        #expect(coach.started == 1)
        #expect(coach.sent == ["Once"])
    }

    @Test func noPermissionYetOpensAndAsksInsteadOfListening() async {
        let session = await makeSession(coach: FakeCoach(), access: .undetermined)

        session.holdBegan()

        #expect(session.mode == .open)
        #expect(session.asksForMicrophone)
        #expect(!session.isHearing)
    }

    @Test func refusedPermissionOpensAndSaysSo() async {
        let session = await makeSession(coach: FakeCoach(), access: .denied)

        session.holdBegan()

        #expect(session.mode == .open)
        #expect(session.asksForMicrophone)
    }

    @Test func aLanguageThisIPhoneCannotHearOpensForTyping() async {
        let session = await makeSession(coach: FakeCoach(), transcriber: HeldTranscriber(hears: nil, available: false))

        session.holdBegan()

        #expect(session.mode == .open)
        #expect(session.wantsKeyboard)
        #expect(!session.asksForMicrophone)
    }

    @Test func anApprovalIsAnsweredAndTheAnswerIsReadAloud() async throws {
        let approval = ToolApproval(messageId: "m9", calls: [.init(name: "log_meal", summary: "Log your lunch")])
        let coach = FakeCoach(reply: [.approval(approval), .done(messageID: nil)], resume: [.token("Logged it."), .done(messageID: "s2")])
        let speaker = FakeSpeaker()
        let session = await makeSession(coach: coach, hears: "Log my lunch", speaker: speaker)

        session.holdBegan()
        try await untilHearing(session)
        await session.holdEnded()
        try await until { session.store?.pendingApproval != nil && session.store?.phase == .ready }
        #expect(speaker.spoken.isEmpty, "the card is read on screen; its summary is not for a voice")

        let store = try #require(session.store)
        await store.decide(approve: true)
        try await untilReplied(session)

        #expect(coach.decisions == [true])
        #expect(store.dataChanges == 2)
        #expect(speaker.spoken == ["Logged it."])
    }

    // MARK: - Helpers

    private func makeSession(
        coach: FakeCoach,
        hears: String? = nil,
        transcriber: HeldTranscriber? = nil,
        speaker: FakeSpeaker = FakeSpeaker(),
        access: Permissions.Access = .granted,
        defaults: UserDefaults? = nil
    ) async -> QuickCoachSession {
        let session = QuickCoachSession(
            coach: coach,
            transcriber: transcriber ?? HeldTranscriber(hears: hears),
            speaker: speaker,
            micAccess: { access },
            defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        )
        await session.prepare()
        return session
    }

    private func untilHearing(_ session: QuickCoachSession) async throws {
        try await until { session.isHearing }
    }

    private func untilReplied(_ session: QuickCoachSession) async throws {
        try await until { session.store?.phase == .ready && session.store?.messages.last?.role == .coach }
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}

// MARK: - Fakes

private final class FakeSpeaker: ReplySpeaking {
    var spoken: [String] = []
    private(set) var stops = 0

    func speak(_ sentence: String) { spoken.append(sentence) }
    func stop() { stops += 1 }
}

/// Hears one phrase, settled when the hold ends; nil hears only silence.
private actor HeldTranscriber: SpeechTranscribing {
    private let phrase: String?
    private let available: Bool
    private let startDelay: Duration?
    private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?
    private(set) var stops = 0

    init(hears phrase: String?, available: Bool = true, startsAfter startDelay: Duration? = nil) {
        self.phrase = phrase
        self.available = available
        self.startDelay = startDelay
    }

    func isAvailable() async -> Bool { available }

    func start() async throws -> AsyncThrowingStream<Transcript, Error> {
        if let startDelay { try? await Task.sleep(for: startDelay) }
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Transcript.self, throwing: Error.self)
        self.continuation = continuation
        return stream
    }

    func stop() async {
        stops += 1
        if let phrase { continuation?.yield(Transcript(text: phrase, isFinal: true)) }
        continuation?.finish()
        continuation = nil
    }
}
