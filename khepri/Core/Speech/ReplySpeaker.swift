import AVFAudio
import NaturalLanguage

/// Reads the coach's replies aloud, one sentence at a time.
protocol ReplySpeaking: AnyObject {
    /// Queues a sentence behind whatever is being read.
    func speak(_ sentence: String)
    /// Stops reading and drops what is queued.
    func stop()
}

/// Reads on this iPhone with the system's voices, in the app's language.
final class SystemReplySpeaker: NSObject, ReplySpeaking, AVSpeechSynthesizerDelegate {
    // Made on first use: a session that is only ever typed in never needs one.
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private var holdsAudio = false

    func speak(_ sentence: String) {
        claimAudio()
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = AVSpeechSynthesisVoice(language: Bundle.main.preferredLocalizations.first)
        synthesizer.speak(utterance)
    }

    func stop() {
        guard holdsAudio else { return }
        synthesizer.stopSpeaking(at: .immediate)
        releaseAudio()
    }

    /// Listening leaves the session on `.record`, which plays nothing. Ambient
    /// is what lets the silent switch mute the coach; music ducks under it.
    private func claimAudio() {
        guard !holdsAudio else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .spokenAudio, options: .duckOthers)
        } catch {
            try? session.setCategory(.ambient, options: .duckOthers)
        }
        try? session.setActive(true)
        holdsAudio = true
    }

    private func releaseAudio() {
        guard holdsAudio else { return }
        holdsAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func wentQuiet() {
        if !synthesizer.isSpeaking { releaseAudio() }
    }

    // The synthesizer calls these off the main actor: an isolated method here
    // would trap.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.wentQuiet() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.wentQuiet() }
    }
}

/// Cuts a reply that is still arriving into sentences to read, so reading
/// starts before the reply ends and no sentence is read twice.
struct ReplySentences {
    private var consumed = 0

    /// The sentences of `text` not yet handed out. Until `finished`, the last
    /// one is held back: more of it may be on its way.
    mutating func take(from text: String, finished: Bool) -> [String] {
        guard text.count > consumed else { return [] }
        let rest = String(text.dropFirst(consumed))
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = rest
        var ranges = tokenizer.tokens(for: rest.startIndex..<rest.endIndex)
        if !finished, !ranges.isEmpty { ranges.removeLast() }
        guard let last = ranges.last else { return [] }
        consumed += rest.distance(from: rest.startIndex, to: last.upperBound)
        return ranges.compactMap { Self.readable(String(rest[$0])) }
    }

    /// What a voice should say for this piece of Markdown: no emphasis marks,
    /// list bullets or headings. Nil when there is nothing to say.
    static func readable(_ markdown: String) -> String? {
        let plain = String(Markdown.render(markdown).characters)
        let text = plain
            .replacing(/^\s*(?:[-*•]|\d+\.|#+)\s+/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.contains(where: { $0.isLetter || $0.isNumber }) ? text : nil
    }
}
