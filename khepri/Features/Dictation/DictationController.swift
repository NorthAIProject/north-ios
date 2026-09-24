import SwiftUI

/// One text field's dictation: listening, and writing what is heard into the
/// field as it is heard.
///
/// The words land in the field, never in a message. The person reads what
/// was heard and sends it themselves, so a mis-heard word is caught by the
/// one party who knows what they said.
@MainActor @Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        /// Asking for the microphone, or downloading the language model the
        /// first time.
        case preparing
        case listening
        case failed(String)
    }

    /// Long enough for a thought, short enough that a forgotten microphone
    /// does not keep listening.
    static let limit: Duration = .seconds(120)

    private(set) var phase: Phase = .idle
    private(set) var isAvailable = false

    private let transcriber: any SpeechTranscribing
    private var session: Task<Void, Never>?

    init(transcriber: any SpeechTranscribing) {
        self.transcriber = transcriber
    }

    var isActive: Bool { phase == .preparing || phase == .listening }

    func checkAvailability() async {
        isAvailable = await transcriber.isAvailable()
    }

    func toggle(_ text: Binding<String>) {
        isActive ? stop() : start(text)
    }

    /// Listens and keeps `text` up to date. Whatever was already typed stays
    /// in front of the spoken words.
    func start(_ text: Binding<String>) {
        let typed = text.wrappedValue
        phase = .preparing
        session = Task {
            do {
                let heard = try await transcriber.start()
                // Stopped while the model was still downloading: that stop
                // ran before the microphone was open, so close it now.
                if Task.isCancelled {
                    await transcriber.stop()
                    phase = .idle
                    return
                }
                phase = .listening
                let timeout = Task { [transcriber] in
                    try await Task.sleep(for: Self.limit)
                    await transcriber.stop()
                }
                defer { timeout.cancel() }

                var settled = ""
                for try await transcript in heard {
                    if transcript.isFinal {
                        settled = Self.join(settled, transcript.text)
                        text.wrappedValue = Self.merge(typed: typed, spoken: settled)
                    } else {
                        text.wrappedValue = Self.merge(typed: typed, spoken: Self.join(settled, transcript.text))
                    }
                }
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops listening. The last words settle before the field stops changing.
    func stop() {
        if phase == .preparing { session?.cancel() }
        Task { [transcriber] in await transcriber.stop() }
    }

    /// Stops listening and drops whatever has not landed yet. For when the
    /// field goes away: a message sent mid-sentence must not have its words
    /// written back into the emptied composer.
    func cancel() {
        guard isActive else { return }
        session?.cancel()
        phase = .idle
        Task { [transcriber] in await transcriber.stop() }
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    /// What was typed, then what was said, with one space between.
    nonisolated static func merge(typed: String, spoken: String) -> String {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return typed }
        return join(typed, spoken)
    }

    /// Two runs of words, with a space between unless one is already there.
    nonisolated static func join(_ first: String, _ second: String) -> String {
        guard let last = first.last else { return second }
        guard let next = second.first else { return first }
        return last.isWhitespace || next.isWhitespace ? first + second : first + " " + second
    }
}
