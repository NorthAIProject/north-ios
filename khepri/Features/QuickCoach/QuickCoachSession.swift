import Foundation
import NorthAPI
import Observation
import SwiftUI

/// One visit to the quick coach, from the hold on Today's orb until the
/// overlay closes: listening, the question, and the same conversation for any
/// follow-ups. The conversation is a normal Coach chat, made when the first
/// message goes, so opening and closing leaves nothing behind.
@MainActor
@Observable
final class QuickCoachSession {
    enum Mode: Equatable {
        case closed
        /// The finger is still down; letting go sends what was heard.
        case listening
        case open
    }

    private(set) var mode: Mode = .closed
    var draft = ""
    private(set) var store: ConversationStore?
    /// The chat this visit made, for continuing it in the Coach tab.
    private(set) var conversation: ConversationSummary?
    /// Settling the last words, or making the chat, before the message goes.
    private(set) var isSubmitting = false
    /// Why the message could not go or the microphone failed; the draft stays.
    private(set) var notice: String?
    /// The person let go without a word being heard.
    private(set) var heardNothing = false
    /// The overlay should ask for the microphone: permission is not there yet.
    private(set) var asksForMicrophone = false
    /// The overlay should bring the keyboard up: typing is the way forward.
    private(set) var wantsKeyboard = false
    /// Spoken replies are off. Remembered between visits.
    var isMuted: Bool {
        didSet {
            defaults.set(isMuted, forKey: Self.mutedKey)
            if isMuted { speaker.stop() }
        }
    }

    @ObservationIgnored private let coach: CoachServicing
    @ObservationIgnored private let dictation: DictationController
    @ObservationIgnored private let speaker: any ReplySpeaking
    @ObservationIgnored private let micAccess: () -> Permissions.Access
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var sentences = ReplySentences()
    /// The next message was spoken, so its reply will be.
    @ObservationIgnored private var draftWasSpoken = false
    @ObservationIgnored private var turnIsSpoken = false
    /// Bumped on close, so work that was waiting does not act on a closed visit.
    @ObservationIgnored private var visit = 0

    private static let mutedKey = "quickCoach.muted"

    init(
        coach: CoachServicing = CoachService(),
        transcriber: any SpeechTranscribing = EnvironmentValues().speechTranscriber,
        speaker: any ReplySpeaking = SystemReplySpeaker(),
        micAccess: @escaping () -> Permissions.Access = { UITesting.isActive ? .granted : Permissions.dictation },
        defaults: UserDefaults = .standard
    ) {
        self.coach = coach
        dictation = DictationController(transcriber: transcriber)
        self.speaker = speaker
        self.micAccess = micAccess
        self.defaults = defaults
        isMuted = defaults.bool(forKey: Self.mutedKey)
    }

    /// Whether the microphone is really open, as opposed to getting ready.
    var isHearing: Bool { dictation.phase == .listening }

    var canSend: Bool {
        let hasWords = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasWords, !isSubmitting else { return false }
        guard let store else { return true }
        if case .failed = store.phase { return true }
        return store.canSendMessage(draft)
    }

    var activity: CoachActivity {
        let listening = mode == .listening
        if let store { return .resolve(store, flash: nil, isListening: listening) }
        return isSubmitting ? .catchingUp : .resolve(phase: .ready, isListening: listening)
    }

    /// Learns whether this iPhone can transcribe the person's language.
    func prepare() async {
        await dictation.checkAvailability()
    }

    /// The hold passed its threshold. Listens if it can; otherwise opens for
    /// typing, since a permission prompt would take the finger away anyway.
    func holdBegan() {
        guard mode == .closed else { return }
        speaker.stop()
        switch (dictation.isAvailable, micAccess()) {
        case (true, .granted):
            mode = .listening
            dictation.start(draftBinding)
        case (true, _):
            mode = .open
            asksForMicrophone = true
        case (false, _):
            mode = .open
            wantsKeyboard = true
        }
    }

    /// The finger came up: the last words settle, then they go. With nothing
    /// heard the overlay stays open to type in.
    func holdEnded() async {
        guard mode == .listening else { return }
        let thisVisit = visit
        mode = .open
        isSubmitting = true
        await dictation.stopAndSettle()
        isSubmitting = false
        guard thisVisit == visit else { return }
        if case .failed(let message) = dictation.phase {
            dictation.dismissError()
            notice = message
            wantsKeyboard = true
            return
        }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            heardNothing = true
            wantsKeyboard = true
            return
        }
        draftWasSpoken = true
        await send()
    }

    /// Opens for typing, without a hold: VoiceOver's way in.
    func openForTyping() {
        guard mode == .closed else { return }
        speaker.stop()
        mode = .open
        wantsKeyboard = true
    }

    /// Dictation in the composer started: the reply to this draft is read out.
    func composerStartedListening() {
        draftWasSpoken = true
        heardNothing = false
    }

    /// Sends the draft, making the chat first if this is the visit's first
    /// message. On failure the draft stays, to try again.
    func send() async {
        guard canSend else { return }
        let thisVisit = visit
        notice = nil
        heardNothing = false
        speaker.stop()
        isSubmitting = true
        defer { isSubmitting = false }
        guard let ready = await readyStore(), thisVisit == visit else { return }

        turnIsSpoken = draftWasSpoken
        draftWasSpoken = false
        sentences = ReplySentences()
        let text = draft
        draft = ""
        ready.send(text)
    }

    /// Stops the reply being written and read. What arrived stays on screen.
    func stopReply() {
        turnIsSpoken = false
        speaker.stop()
        store?.stop()
    }

    /// The app left the foreground: nobody is there to hear the rest.
    func leftForeground() {
        turnIsSpoken = false
        speaker.stop()
    }

    func close() {
        visit += 1
        dictation.cancel()
        speaker.stop()
        store?.onReplyProgress = nil
        store?.stop()
        store = nil
        conversation = nil
        draft = ""
        notice = nil
        heardNothing = false
        asksForMicrophone = false
        wantsKeyboard = false
        isSubmitting = false
        draftWasSpoken = false
        turnIsSpoken = false
        sentences = ReplySentences()
        mode = .closed
    }

    private var draftBinding: Binding<String> {
        Binding(get: { self.draft }, set: { self.draft = $0 })
    }

    private func readyStore() async -> ConversationStore? {
        if let store {
            if case .failed = store.phase { await store.load() }
            return ready(store)
        }
        let thisVisit = visit
        do {
            let started = try await coach.start(reflection: false)
            guard thisVisit == visit else { return nil }
            let store = ConversationStore(conversationID: started.id, title: started.title, coach: coach)
            store.onReplyProgress = { [weak self] text, finished in
                self?.replyProgressed(text, finished: finished)
            }
            conversation = started
            self.store = store
            await store.load()
            return ready(store)
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    private func ready(_ store: ConversationStore) -> ConversationStore? {
        if case .failed(let message) = store.phase {
            notice = message
            return nil
        }
        return store
    }

    private func replyProgressed(_ text: String, finished: Bool) {
        // Taken even when muted, so unmuting does not read the reply from the top.
        let due = sentences.take(from: text, finished: finished)
        if finished { sentences = ReplySentences() }
        guard turnIsSpoken, !isMuted else { return }
        due.forEach(speaker.speak)
    }
}
