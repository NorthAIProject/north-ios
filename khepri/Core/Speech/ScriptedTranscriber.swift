#if DEBUG
import Foundation

/// Hears the same sentence every time. The UI tests run in a simulator with
/// no microphone, so this stands in for `OnDeviceTranscriber` under test.
actor ScriptedTranscriber: SpeechTranscribing {
    static let phrase = "How many rest days should I take"

    private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?

    func isAvailable() async -> Bool { true }

    func start() async throws -> AsyncThrowingStream<Transcript, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Transcript.self, throwing: Error.self)
        continuation.yield(Transcript(text: "How many rest", isFinal: false))
        self.continuation = continuation
        return stream
    }

    func stop() async {
        continuation?.yield(Transcript(text: Self.phrase, isFinal: true))
        continuation?.finish()
        continuation = nil
    }
}
#endif
