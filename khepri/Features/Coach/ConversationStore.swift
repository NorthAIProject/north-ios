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
    var helpful: Bool?
    var isStreaming = false
    /// Whether this has a server id, so it can be rated.
    var isStored = true

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role == .coach ? .coach : .user
        text = message.text
        exercises = message.exercises
        helpful = message.helpful
    }

    init(localID: String = UUID().uuidString, role: Role, text: String, isStreaming: Bool = false) {
        id = localID
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        isStored = false
    }
}

/// Drives one conversation: history, sending, the streamed reply, approvals
/// and ratings.
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
    private(set) var phase: Phase = .loading
    /// A reply that failed, shown under the conversation, kept apart from the
    /// messages so a retry does not leave it behind.
    private(set) var replyError: String?
    private(set) var ended = false

    private let coach: CoachServicing
    private var replyTask: Task<Void, Never>?
    /// The reply being written. Its id changes once, from local to the
    /// server's, when `done` arrives.
    private var replyID: String?

    init(conversationID: String, title: String, coach: CoachServicing = CoachService()) {
        self.conversationID = conversationID
        self.title = title
        self.coach = coach
    }

    var canSend: Bool { phase == .ready && pendingApproval == nil && !ended }

    func load() async {
        do {
            let detail = try await coach.conversation(conversationID)
            title = detail.conversation.title
            ended = detail.conversation.ended
            messages = detail.messages.map(DisplayMessage.init)
            pendingApproval = detail.pendingApproval
            phase = .ready
            // Answered on another device, reply still owed: collect it.
            if detail.awaitingResume {
                stream(coach.resume(conversationID))
            }
        } catch {
            if messages.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    /// Sends a message and streams the reply into the conversation.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        messages.append(DisplayMessage(role: .user, text: text))
        stream(coach.reply(in: conversationID, text: text))
    }

    /// Allows or refuses what the coach asked to do, then collects the reply.
    func decide(approve: Bool) async {
        guard let approval = pendingApproval else { return }
        do {
            try await coach.decide(in: conversationID, messageID: approval.messageId, approve: approve)
            pendingApproval = nil
            stream(coach.resume(conversationID))
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

    private func stream(_ events: AsyncThrowingStream<CoachEvent, Error>) {
        replyError = nil
        phase = .replying
        let reply = DisplayMessage(role: .coach, text: "", isStreaming: true)
        messages.append(reply)
        replyID = reply.id

        replyTask = Task { [weak self] in
            do {
                for try await event in events {
                    self?.apply(event)
                }
            } catch is CancellationError {
            } catch {
                self?.replyError = error.localizedDescription
            }
            self?.finishReply()
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
