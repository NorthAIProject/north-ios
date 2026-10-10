import NorthAPI
import NorthKit
import SwiftUI

/// One conversation: the messages, the reply as it streams, exercise cards,
/// approvals, and the composer.
struct ConversationView: View {
    @State private var store: ConversationStore
    @State private var draft = ""
    @State private var openExercise: String?
    @State private var dictating = false
    /// Asking where the next message's file comes from.
    @State private var attaching = false
    /// The moment after a reply ends, while the header says so.
    @State private var flash: CoachActivity.Flash?
    /// Whether the person stopped the reply, which earns no "is done".
    @State private var stopped = false
    @FocusState private var composing: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router

    /// Starts another conversation or reflection from the header.
    private let onNew: (_ reflection: Bool) -> Void

    init(summary: ConversationSummary, coach: CoachServicing, onNew: @escaping (_ reflection: Bool) -> Void = { _ in }) {
        _store = State(initialValue: ConversationStore(conversationID: summary.id, title: summary.title, coach: coach))
        self.onNew = onNew
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.messages) { message in
                        MessageRow(
                            message: message,
                            onExercise: { openExercise = $0 },
                            onRate: { helpful in Task { await store.rate(message, helpful: helpful) } }
                        )
                        .id(message.id)
                    }
                    if let approval = store.pendingApproval {
                        ApprovalCard(approval: approval, isBusy: store.isDeciding || store.isAwaitingReply) { approve in
                            stopped = false
                            Task { await store.decide(approve: approve) }
                        }
                    }
                    if store.isAwaitingReply, store.phase == .ready {
                        StillThinkingRow()
                    }
                    if let note = store.replyNote {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = store.replyError {
                        Label(error, systemImage: "exclamationmark.bubble")
                            .font(.subheadline)
                            .foregroundStyle(NorthColor.destructive)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .refreshable { await store.refresh() }
            .onChange(of: store.messages.last?.text) {
                proxy.scrollTo(bottom, anchor: .bottom)
            }
            .onChange(of: store.pendingApproval) {
                withAnimation { proxy.scrollTo(bottom, anchor: .bottom) }
            }
        }
        .overlay {
            switch store.phase {
            case .loading where store.messages.isEmpty:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView("Could not open this conversation", systemImage: "wifi.exclamationmark", description: Text(message))
            default:
                if store.messages.isEmpty, store.phase == .ready {
                    ContentUnavailableView("Ask anything", systemImage: "bubble.left", description: Text("Try “How do I do a push-up?”"))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.ended {
                Composer(
                    text: $draft,
                    isReplying: store.phase == .replying,
                    canSend: store.canSendMessage(draft),
                    focused: $composing,
                    onListeningChange: { dictating = $0 },
                    onAttach: { attaching = true }
                ) {
                    stopped = false
                    store.send(draft)
                    draft = ""
                } onStop: {
                    stopped = true
                    store.stop()
                } attachments: {
                    if store.isUploading || store.attachment != nil || store.attachmentError != nil {
                        PendingAttachmentBar(
                            attachment: store.attachment,
                            uploadingName: store.uploadingName,
                            error: store.attachmentError,
                            onRemove: store.removeAttachment
                        )
                    }
                }
            } else {
                Text("This reflection has ended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.bar)
            }
        }
        // Khepri's mark in place of the navigation bar: its ring and status
        // say whether the coach is thinking, writing or listening.
        .safeAreaInset(edge: .top, spacing: 0) {
            CoachHeader(
                activity: .resolve(store, flash: flash, isListening: composing || dictating),
                leadingSystemImage: "chevron.left",
                leadingLabel: "Back",
                newIdentifier: "thread-new-conversation",
                onLeading: { dismiss() },
                onNew: onNew
            )
        }
        .onChange(of: store.phase) { old, new in
            if let earned = CoachActivity.flash(
                from: old, to: new,
                // A reply cut off mid-way has not finished, whatever the phase says.
                replyFailed: store.replyError != nil || store.isAwaitingReply,
                awaitingApproval: store.pendingApproval != nil,
                stopped: stopped
            ) {
                flash = earned
            }
        }
        .coachFlash($flash)
        .navigationTitle(store.title)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .interactivePopEnabled()
        // A thread is a place to write, as in Messages: the tab bar would
        // crowd the composer.
        .toolbar(.hidden, for: .tabBar)
        .task { await store.load() }
        // Back from the background or the lock screen: collect a reply that
        // was cut off. Leaving the foreground cancels the asking.
        .task(id: scenePhase) {
            if scenePhase == .active { await store.recoverIfNeeded() }
        }
        .importSourcePicker(
            "Attach to your message",
            message: "A photo, or a PDF, Word, Excel (.xlsx), CSV, text or JSON file. Up to 8 MB.",
            isPresented: $attaching,
            onPick: { store.attach($0) },
            onError: { store.attachmentFailed($0) }
        )
        // An approved action may have written a check-in, a plan or a meal:
        // the screens showing them reload.
        .onChange(of: store.dataChanges) { router.dataChanged() }
        .sheet(item: Binding(get: { openExercise.map(ExerciseSlug.init) }, set: { openExercise = $0?.id })) { slug in
            ExerciseSheet(slug: slug.id)
        }
    }

    private let bottom = "bottom"
}

private struct ExerciseSlug: Identifiable {
    let id: String
}

/// A user message as a tinted bubble on the right, under the files it
/// carried; a coach reply as plain text on the left, with its exercise cards
/// and a way to say it helped.
private struct MessageRow: View {
    let message: DisplayMessage
    let onExercise: (String) -> Void
    let onRate: (Bool) -> Void

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(message.attachments, id: \.mediaId) { attachment in
                    AttachmentChip(attachment: attachment)
                }
                // A message may be only a file.
                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NorthColor.signal.opacity(0.18), in: .rect(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
        case .coach:
            VStack(alignment: .leading, spacing: 12) {
                if message.text.isEmpty && message.isStreaming {
                    TypingIndicator()
                } else {
                    Text(Markdown.render(message.text))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(message.exercises, id: \.self) { slug in
                    ExerciseCard(slug: slug) { onExercise(slug) }
                }
                if message.isStored && !message.isStreaming {
                    HelpfulControl(helpful: message.helpful, onRate: onRate)
                }
            }
        }
    }
}

/// Renders the coach's Markdown: emphasis, links, code and lists, keeping
/// line breaks. Falls back to the plain text rather than showing nothing.
enum Markdown {
    static func render(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct HelpfulControl: View {
    let helpful: Bool?
    let onRate: (Bool) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button { onRate(true) } label: {
                Image(systemName: helpful == true ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .accessibilityLabel("Helpful")
            .accessibilityAddTraits(helpful == true ? .isSelected : [])
            Button { onRate(false) } label: {
                Image(systemName: helpful == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .accessibilityLabel("Not helpful")
            .accessibilityAddTraits(helpful == false ? .isSelected : [])
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: helpful)
    }
}

/// The connection dropped mid-reply and the server is still writing it.
private struct StillThinkingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            TypingIndicator()
            Text("Still thinking…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your coach is still thinking")
    }
}

private struct TypingIndicator: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title3)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .accessibilityLabel("Coach is writing")
    }
}

/// The coach wants to change something and waits for a yes.
private struct ApprovalCard: View {
    let approval: ToolApproval
    /// The answer is on its way; both buttons wait until it lands.
    let isBusy: Bool
    let onDecide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your coach wants to", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NorthColor.agent)
            ForEach(approval.calls, id: \.summary) { call in
                Text(call.summary)
                    .font(.subheadline)
            }
            HStack {
                Button("Not Now") { onDecide(false) }
                    .buttonStyle(.bordered)
                Button { onDecide(true) } label: {
                    if isBusy {
                        ProgressView().accessibilityLabel("Allowing")
                    } else {
                        Text("Allow")
                    }
                }
                .northProminentButton()
            }
            .disabled(isBusy)
        }
        .northCard()
        .overlay {
            RoundedRectangle(cornerRadius: NorthRadius.medium)
                .strokeBorder(NorthColor.agent.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct Composer<Attachments: View>: View {
    @Binding var text: String
    let isReplying: Bool
    /// Whether the message as typed, with its file, can go now.
    let canSend: Bool
    var focused: FocusState<Bool>.Binding
    let onListeningChange: (Bool) -> Void
    let onAttach: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    /// The file the next message carries, shown above the field.
    @ViewBuilder let attachments: () -> Attachments

    var body: some View {
        VStack(spacing: 8) {
            attachments()
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "paperclip").font(.title3)
                }
                .padding(.bottom, 6)
                .accessibilityLabel("Attach a file or photo")

                TextField("Message your coach", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    // The placeholder names the field only while it is empty.
                    .accessibilityIdentifier("composer")
                    .focused(focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))

                // The keyboard's microphone only appears once the keyboard is up
                // and stops on a pause; this one is a tap away and keeps
                // listening until tapped again.
                if !isReplying {
                    DictationButton(text: $text, onListeningChange: onListeningChange)
                }

                if isReplying {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill").font(.title)
                    }
                    .accessibilityLabel("Stop")
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
