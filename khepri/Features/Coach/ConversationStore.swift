import Foundation
import NorthAPI
import Observation

/// One message as the conversation screen shows it: stored history, plus the
/// reply that is still arriving.
struct DisplayMessage: Identifiable, Equatable {
    enum Role { case user, coach }

    /// The server's id once stored; a local one until then.
    var id: String
    var role: Role
    var text: String
    var exercises: [String] = []
    /// Photos and documents the person sent with the message.
    var attachments: [ChatAttachment] = []
    var helpful: Bool?
    var isStreaming = false
    /// Whether this has a server id, so it can be rated.
    var isStored = true

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role == .coach ? .coach : .user
        text = message.text
        exercises = message.exercises
        attachments = message.attachments
        helpful = message.helpful
    }

    init(
        localID: String = UUID().uuidString,
        role: Role,
        text: String,
        attachments: [ChatAttachment] = [],
        isStreaming: Bool = false
    ) {
        id = localID
        self.role = role
        self.text = text
        self.attachments = attachments
        self.isStreaming = isStreaming
        isStored = false
    }
}

/// Drives one conversation: history, sending, the streamed reply, approvals,
/// ratings, and the file the next message carries.
@MainActor
@Observable
final class ConversationStore {
    enum Phase: Equatable {
        case loading
        case ready
        /// The coach is writing.
        case replying
        case failed(String)
    }

    let conversationID: String
    private(set) var title: String
    private(set) var messages: [DisplayMessage] = []
    private(set) var pendingApproval: ToolApproval?
    /// An answer to the approval is on its way and the tools are running.
    private(set) var isDeciding = false
    private(set) var phase: Phase = .loading
    /// A reply that failed, shown under the conversation, kept apart from the
    /// messages so a retry does not leave it behind.
    private(set) var replyError: String?
    private(set) var ended = false
    /// Counts the moments an approved action may have changed the person's
    /// data: when the approval is accepted and when the reply after it ends,
    /// since the tools may still be writing until then. The view passes each
    /// one on to `AppRouter.dataChanged()`.
    private(set) var dataChanges = 0
    /// A photo or document uploaded for the next message to carry. It belongs
    /// to this conversation: leaving with one pending drops it.
    private(set) var attachment: ChatAttachment?
    /// The name of the file on its way up, shown until the server has it.
    private(set) var uploadingName: String?
    /// Why the last file could not be attached.
    private(set) var attachmentError: String?
    /// Said, not as an error, when a reply the app lost track of has not
    /// reached the server's history after a minute of asking.
    private(set) var replyNote: String?

    /// The coach is still working on a reply or approved tools the app
    /// stopped hearing about, as when the phone locked mid-reply.
    var isAwaitingReply: Bool { owed != nil }

    /// The largest file the server keeps for a chat turn.
    static let maxAttachmentBytes = 8 * 1024 * 1024

    /// What the server owes after the app stopped listening.
    private enum Owed {
        /// A reply, cut off or not yet written.
        case reply
        /// Approved tools still running, then their reply.
        case decision
    }

    private let coach: CoachServicing
    private let recovery: ReplyRecovery
    private var replyTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    /// The reply being written. Its id changes once, from local to the
    /// server's, when `done` arrives.
    private var replyID: String?
    private var owed: Owed?
    private var isPolling = false

    init(
        conversationID: String,
        title: String,
        coach: CoachServicing = CoachService(),
        recovery: ReplyRecovery = .standard
    ) {
        self.conversationID = conversationID
        self.title = title
        self.coach = coach
        self.recovery = recovery
    }

    var canSend: Bool { phase == .ready && pendingApproval == nil && !ended && owed == nil }

    var isUploading: Bool { uploadingName != nil }

    /// Whether a message with this text can go now: it needs words or an
    /// uploaded file, and waits for one still uploading.
    func canSendMessage(_ text: String) -> Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return canSend && !isUploading && (hasText || attachment != nil)
    }

    /// Opens the conversation. A reply still owed (answered elsewhere, or a
    /// message sent moments ago that has no answer yet) is collected.
    func load() async {
        do {
            let detail = try await coach.conversation(conversationID)
            show(detail)
            phase = .ready
            // Answered on another device, reply still owed: collect it.
            if detail.awaitingResume {
                stream(coach.resume(conversationID), changesData: true)
                return
            }
            if owed == nil, replyTask == nil, ReplyRecovery.replyInFlight(detail) {
                owed = .reply
            }
        } catch {
            if messages.isEmpty { phase = .failed(error.localizedDescription) }
        }
        await recoverIfNeeded()
    }

    /// Pull to refresh: the stored conversation, once, without waiting on a
    /// reply that is not there yet.
    func refresh() async {
        guard phase != .replying, !isPolling, !isDeciding else { return }
        replyNote = nil
        guard let detail = try? await coach.conversation(conversationID) else { return }
        show(detail)
        if detail.awaitingResume {
            owed = nil
            stream(coach.resume(conversationID), changesData: true)
        } else if owed != nil, !ReplyRecovery.stillOwed(after: detail, waitingOnTools: owed == .decision) {
            owed = nil
        }
    }

    /// Collects a reply the app stopped hearing: asks the server for the
    /// conversation every `pollInterval` until the reply is stored, resuming
    /// it if the server is waiting for that, or gives up gently. Called when
    /// a reply is cut off in the foreground and when the app comes back.
    func recoverIfNeeded() async {
        guard owed != nil, phase == .ready, !isPolling, !recovery.isInBackground() else { return }
        isPolling = true
        defer { isPolling = false }
        for attempt in 0..<recovery.attempts {
            // Cancelled: the screen or the foreground was left; owed stays for next time.
            if attempt > 0, (try? await Task.sleep(for: recovery.pollInterval)) == nil { return }
            guard let detail = try? await coach.conversation(conversationID), !Task.isCancelled else { continue }
            show(detail)
            if detail.awaitingResume {
                owed = nil
                stream(coach.resume(conversationID), changesData: true)
                return
            }
            if !ReplyRecovery.stillOwed(after: detail, waitingOnTools: owed == .decision) {
                owed = nil
                return
            }
        }
        guard !Task.isCancelled else { return }
        owed = nil
        replyNote = "Your coach's reply will appear here when it's ready — pull to refresh."
    }

    /// The conversation as the server stores it, replacing whatever the
    /// screen pieced together from a stream.
    private func show(_ detail: ConversationDetail) {
        title = detail.conversation.title
        ended = detail.conversation.ended
        let stored = detail.messages.map(DisplayMessage.init)
        if stored != messages { messages = stored }
        pendingApproval = detail.pendingApproval
    }

    /// The connection was cut while the server still owed `what`: show the
    /// coach as still thinking rather than failed.
    private func markInterrupted(owing what: Owed) {
        owed = what
        replyError = nil
        replyNote = nil
    }

    /// Sends a message, with the pending attachment if there is one, and
    /// streams the reply into the conversation.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendMessage(text) else { return }
        let carried = attachment
        attachment = nil
        attachmentError = nil
        replyNote = nil
        messages.append(DisplayMessage(role: .user, text: text, attachments: carried.map { [$0] } ?? []))
        stream(coach.reply(in: conversationID, text: text, mediaID: carried?.mediaId))
    }

    /// Uploads a photo or document for the next message, replacing any
    /// pending one. It goes up now, so sending does not wait on it.
    func attach(_ file: ImportFile) {
        removeAttachment()
        guard file.data.count <= Self.maxAttachmentBytes else {
            attachmentError = "That file is larger than 8 MB."
            return
        }
        uploadingName = file.filename
        let coach = coach
        let conversationID = conversationID
        uploadTask = Task { [weak self] in
            do {
                let uploaded = try await coach.uploadAttachment(in: conversationID, file: file)
                guard !Task.isCancelled else { return }
                self?.attachment = uploaded
            } catch {
                // Removed while uploading: the person no longer wants it.
                guard !Task.isCancelled else { return }
                self?.attachmentError = Self.uploadMessage(for: error)
            }
            self?.uploadingName = nil
            self?.uploadTask = nil
        }
    }

    /// An old server has no upload route and answers 404 or 405; the generic
    /// "could not be found" would read as the conversation being gone.
    private static func uploadMessage(for error: any Error) -> String {
        if let api = error as? APIError {
            if api.isNotFound { return "Attachments aren't available yet." }
            if case .invalidStatus(405) = api { return "Attachments aren't available yet." }
        }
        return error.importMessage
    }

    /// Drops the pending attachment, or stops the one still uploading.
    func removeAttachment() {
        uploadTask?.cancel()
        uploadTask = nil
        uploadingName = nil
        attachment = nil
        attachmentError = nil
    }

    /// A file the picker could not read never reaches `attach`; its reason
    /// shows where an upload's would.
    func attachmentFailed(_ message: String) {
        attachmentError = message
    }

    /// Allows or refuses what the coach asked to do, then collects the reply.
    ///
    /// A write such as a new training plan runs for minutes before this
    /// returns, so a second tap in the meantime is ignored rather than sent.
    /// The server runs the tools even if the app stops listening, and answers
    /// 409 while they run, so a cut connection or a 409 waits for them.
    func decide(approve: Bool) async {
        guard let approval = pendingApproval, !isDeciding, owed == nil else { return }
        isDeciding = true
        defer { isDeciding = false }
        replyError = nil
        replyNote = nil
        do {
            try await coach.decide(in: conversationID, messageID: approval.messageId, approve: approve)
            pendingApproval = nil
            if approve { dataChanges += 1 }
            stream(coach.resume(conversationID), changesData: approve)
        } catch where ReplyRecovery.isInterruption(error) || APIError(error).isConflict {
            if approve { dataChanges += 1 }
            markInterrupted(owing: .decision)
            // In the background this waits for the app to come back.
            await recoverIfNeeded()
        } catch {
            replyError = error.localizedDescription
        }
    }

    /// Rates a stored coach reply; tapping the current answer clears it.
    func rate(_ message: DisplayMessage, helpful: Bool) async {
        guard message.isStored, let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let answer: Bool? = message.helpful == helpful ? nil : helpful
        messages[index].helpful = answer
        do {
            _ = try await coach.rate(in: conversationID, messageID: message.id, helpful: answer)
        } catch {
            messages[index].helpful = message.helpful
        }
    }

    /// Stops the reply being written. What arrived so far stays on screen.
    func stop() {
        replyTask?.cancel()
    }

    /// Streams a reply in. `changesData` marks a reply that runs approved
    /// tools, which counts as a change once it ends.
    private func stream(_ events: AsyncThrowingStream<CoachEvent, Error>, changesData: Bool = false) {
        replyError = nil
        phase = .replying
        let reply = DisplayMessage(role: .coach, text: "", isStreaming: true)
        messages.append(reply)
        replyID = reply.id

        replyTask = Task { [weak self] in
            var cutOff = false
            do {
                for try await event in events {
                    self?.apply(event)
                }
            } catch is CancellationError {
            } catch where ReplyRecovery.isInterruption(error) {
                // Marked before the phase changes, so the end earns no "done".
                self?.markInterrupted(owing: .reply)
                cutOff = true
            } catch {
                self?.replyError = error.localizedDescription
            }
            self?.finishReply()
            if changesData { self?.dataChanges += 1 }
            // In the background this waits for the app to come back.
            if cutOff { await self?.recoverIfNeeded() }
        }
    }

    private func apply(_ event: CoachEvent) {
        guard let index = messages.firstIndex(where: { $0.id == replyID }) else { return }
        switch event {
        case .token(let text):
            messages[index].text += text
        case .exercises(let slugs):
            messages[index].exercises = slugs
        case .approval(let approval):
            pendingApproval = approval
        case .failed(let message):
            replyError = message
        case .done(let messageID):
            if let messageID {
                messages[index].id = messageID
                messages[index].isStored = true
                replyID = messageID
            }
        }
    }

    private func finishReply() {
        if let index = messages.firstIndex(where: { $0.id == replyID }) {
            messages[index].isStreaming = false
            // A turn that stopped to ask, or failed before a word, leaves no
            // empty bubble behind.
            if messages[index].text.isEmpty && messages[index].exercises.isEmpty {
                messages.remove(at: index)
            }
        }
        phase = .ready
        replyTask = nil
        replyID = nil
    }
}
