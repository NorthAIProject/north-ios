import Foundation

/// A stretch of speech turned into words.
///
/// Volatile transcripts are a best guess that the next one replaces; a final
/// transcript is settled and the words after it start fresh.
nonisolated struct Transcript: Sendable, Equatable {
    var text: String
    var isFinal: Bool
}

/// Something that listens to the microphone and writes down what it hears.
///
/// One session at a time: `start` begins listening and returns the words as
/// they are heard; `stop` ends the input, lets the last words settle, and the
/// stream finishes after the final transcript.
protocol SpeechTranscribing: Sendable {
    /// Whether this device can transcribe the person's language at all. False
    /// hides the microphone rather than offering one that cannot work.
    func isAvailable() async -> Bool
    func start() async throws -> AsyncThrowingStream<Transcript, Error>
    func stop() async
}

nonisolated enum DictationError: LocalizedError, Equatable {
    case unsupportedLocale
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale: "Dictation does not support your language on this iPhone yet."
        case .noMicrophone: "No microphone is available."
        }
    }
}
