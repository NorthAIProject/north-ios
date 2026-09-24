import SwiftUI
import Testing
@testable import khepri

struct DictationMergeTests {
    @Test func spokenWordsFollowWhatWasTyped() {
        #expect(DictationController.merge(typed: "", spoken: "hello") == "hello")
        #expect(DictationController.merge(typed: "I ran", spoken: "five kilometres") == "I ran five kilometres")
        #expect(DictationController.merge(typed: "I ran ", spoken: "five") == "I ran five")
        #expect(DictationController.merge(typed: "Line one\n", spoken: "two") == "Line one\ntwo")
    }

    @Test func silenceLeavesTheFieldAlone() {
        #expect(DictationController.merge(typed: "typed", spoken: "") == "typed")
        #expect(DictationController.merge(typed: "typed", spoken: "   ") == "typed")
    }

    @Test func settledRunsAreJoinedWithOneSpace() {
        #expect(DictationController.join("", "one") == "one")
        #expect(DictationController.join("one", "") == "one")
        #expect(DictationController.join("one", "two") == "one two")
        #expect(DictationController.join("one", " two") == "one two")
    }
}

@MainActor
struct DictationControllerTests {
    @Test func writesVolatileThenSettledWordsAfterTypedText() async throws {
        let transcriber = FakeTranscriber()
        let field = Field("Today")
        let controller = DictationController(transcriber: transcriber)

        controller.start(field.binding)
        try await until { controller.phase == .listening }

        await transcriber.send(Transcript(text: "I sle", isFinal: false))
        try await until { field.text == "Today I sle" }

        await transcriber.send(Transcript(text: "I slept badly.", isFinal: true))
        await transcriber.send(Transcript(text: "Tired", isFinal: false))
        try await until { field.text == "Today I slept badly. Tired" }

        controller.stop()
        try await until { controller.phase == .idle }
        #expect(field.text == "Today I slept badly. Tired now")
    }

    @Test func cancellingDropsWordsThatHaveNotLanded() async throws {
        let transcriber = FakeTranscriber()
        let field = Field("")
        let controller = DictationController(transcriber: transcriber)

        controller.start(field.binding)
        try await until { controller.phase == .listening }
        await transcriber.send(Transcript(text: "Sent already", isFinal: true))
        try await until { field.text == "Sent already" }

        field.text = ""
        controller.cancel()
        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.phase == .idle)
        #expect(field.text == "")
    }

    @Test func aFailureIsShownAndCanBeDismissed() async throws {
        let transcriber = FakeTranscriber(failure: DictationError.unsupportedLocale)
        let controller = DictationController(transcriber: transcriber)

        controller.start(Field("").binding)
        try await until { controller.phase != .preparing }

        #expect(controller.phase == .failed(DictationError.unsupportedLocale.localizedDescription))
        controller.dismissError()
        #expect(controller.phase == .idle)
    }

    @Test func availabilityComesFromTheTranscriber() async {
        let controller = DictationController(transcriber: FakeTranscriber(available: false))
        await controller.checkAvailability()
        #expect(!controller.isAvailable)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}

// MARK: - Fakes

@MainActor
private final class Field {
    var text: String
    init(_ text: String) { self.text = text }
    var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

/// Hears whatever the test sends; `stop` settles one last word, as the real
/// analyzer settles the volatile tail.
private actor FakeTranscriber: SpeechTranscribing {
    private let available: Bool
    private let failure: Error?
    private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?

    init(available: Bool = true, failure: Error? = nil) {
        self.available = available
        self.failure = failure
    }

    func isAvailable() async -> Bool { available }

    func start() async throws -> AsyncThrowingStream<Transcript, Error> {
        if let failure { throw failure }
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Transcript.self, throwing: Error.self)
        self.continuation = continuation
        return stream
    }

    func send(_ transcript: Transcript) {
        continuation?.yield(transcript)
    }

    func stop() async {
        continuation?.yield(Transcript(text: "Tired now", isFinal: true))
        continuation?.finish()
        continuation = nil
    }
}
