import NorthAPI
import NorthKit
import SwiftUI

/// One conversation: the messages, the reply as it streams, exercise cards,
/// approvals, and the composer.
struct ConversationView: View {
    @State private var store: ConversationStore
    @State private var draft = ""
    @State private var openExercise: String?
    @FocusState private var composing: Bool

    init(summary: ConversationSummary, coach: CoachServicing) {
        _store = State(initialValue: ConversationStore(conversationID: summary.id, title: summary.title, coach: coach))
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
                        ApprovalCard(approval: approval) { approve in
                            Task { await store.decide(approve: approve) }
                        }
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
                Composer(text: $draft, isReplying: store.phase == .replying, canSend: store.canSend, focused: $composing) {
                    store.send(draft)
                    draft = ""
                } onStop: {
                    store.stop()
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
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        // A thread is a place to write, as in Messages: the tab bar would
        // crowd the composer.
        .toolbar(.hidden, for: .tabBar)
        .task { await store.load() }
        .sheet(item: Binding(get: { openExercise.map(ExerciseSlug.init) }, set: { openExercise = $0?.id })) { slug in
            ExerciseSheet(slug: slug.id)
        }
    }

    private let bottom = "bottom"
}

private struct ExerciseSlug: Identifiable {
    let id: String
}

/// A user message as a tinted bubble on the right; a coach reply as plain
/// text on the left, with its exercise cards and a way to say it helped.
private struct MessageRow: View {
    let message: DisplayMessage
    let onExercise: (String) -> Void
    let onRate: (Bool) -> Void

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NorthColor.signal.opacity(0.18), in: .rect(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
                .textSelection(.enabled)
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
                Button("Allow") { onDecide(true) }
                    .northProminentButton()
            }
        }
        .northCard()
        .overlay {
            RoundedRectangle(cornerRadius: NorthRadius.medium)
                .strokeBorder(NorthColor.agent.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct Composer: View {
    @Binding var text: String
    let isReplying: Bool
    let canSend: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void

    private var trimmedEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message your coach", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))

            // The keyboard's microphone only appears once the keyboard is up
            // and stops on a pause; this one is a tap away and keeps
            // listening until tapped again.
            if !isReplying {
                DictationButton(text: $text)
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
                .disabled(!canSend || trimmedEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
