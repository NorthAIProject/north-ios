import NorthAPI
import NorthKit
import SwiftUI

extension View {
    /// Shows the quick coach above everything in this view, tab bar included.
    ///
    /// In the view tree rather than a sheet: presenting a sheet would cancel
    /// the touch on the orb, and letting go is what sends the message.
    func quickCoachOverlay(_ session: QuickCoachSession) -> some View {
        modifier(QuickCoachPresenter(session: session))
    }
}

private struct QuickCoachPresenter: ViewModifier {
    let session: QuickCoachSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if session.mode != .closed {
                    QuickCoachOverlay(session: session)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15), value: session.mode == .closed)
    }
}

/// The card that rises from the bottom of the screen: what was heard, the
/// reply, anything the coach needs an Allow for, and a composer for more.
struct QuickCoachOverlay: View {
    let session: QuickCoachSession

    /// How much of the screen the conversation may take before it scrolls.
    private static let messagesShare: CGFloat = 0.6

    @State private var messagesHeight: CGFloat = 0
    @FocusState private var composing: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { session.close() }
                    .accessibilityHidden(true)
                card(maxMessagesHeight: proxy.size.height * Self.messagesShare)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        // The finger that opened this is still on the orb underneath.
        .allowsHitTesting(session.mode != .listening)
        .onAppear { composing = session.wantsKeyboard }
        .onChange(of: session.wantsKeyboard) { _, wants in composing = wants }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.leftForeground() }
        }
        // Back from the background: collect a reply that was cut off.
        .task(id: scenePhase) {
            if scenePhase == .active { await session.store?.recoverIfNeeded() }
        }
        // An approved action may have written a check-in, a plan or a meal.
        .onChange(of: session.store?.dataChanges ?? 0) { old, new in
            if new > old { router.dataChanged() }
        }
        .sensoryFeedback(.start, trigger: session.isHearing) { _, hearing in hearing }
        .sensoryFeedback(.warning, trigger: session.store?.pendingApproval != nil) { _, asking in asking }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { session.close() }
    }

    private func card(maxMessagesHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            if session.mode == .listening {
                listening
            } else {
                messages(maxHeight: maxMessagesHeight)
                composer
            }
        }
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            NorthBrand.mark
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 36, height: 36)
                .background(CoachHeaderMetrics.pill, in: Circle())
                .overlay { CoachRing(mood: session.activity.mood).padding(-CoachHeaderMetrics.ringInset) }
                .accessibilityHidden(true)
                .padding(.horizontal, CoachHeaderMetrics.ringInset)
            VStack(alignment: .leading, spacing: 0) {
                Text(NorthBrand.name)
                    .font(.north(.subheadline).weight(.semibold))
                Text(session.activity.status)
                    .font(.north(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("quick-coach-status")
            Spacer(minLength: 0)
            if session.mode != .listening {
                actions
            }
        }
        .padding(12)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if let conversation = session.conversation {
                iconButton("arrow.up.left.and.arrow.down.right", label: "Open in chat", identifier: "quick-coach-open-chat") {
                    // Closed first: changing tab closes it too.
                    session.close()
                    router.open(.conversation(conversation))
                }
            }
            iconButton(
                session.isMuted ? "speaker.slash" : "speaker.wave.2",
                label: session.isMuted ? "Read replies aloud" : "Stop reading replies aloud",
                identifier: "quick-coach-mute"
            ) {
                session.isMuted.toggle()
            }
            iconButton("xmark", label: "Close", identifier: "quick-coach-close") {
                session.close()
            }
        }
    }

    private func iconButton(
        _ systemImage: String,
        label: LocalizedStringKey,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var listening: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(NorthColor.agent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: session.isHearing)
                .accessibilityHidden(true)
            Group {
                if !session.draft.isEmpty {
                    Text(session.draft)
                } else if session.isHearing {
                    Text("Listening…")
                } else {
                    Text("Getting ready…")
                }
            }
            .font(.north(.title3))
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("quick-coach-heard")
            Text("Let go to send")
                .font(.north(.footnote))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func messages(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let store = session.store {
                        ForEach(store.messages) { message in
                            MessageRow(
                                message: message,
                                onExercise: { router.openExercise = $0 },
                                onRate: { helpful in Task { await store.rate(message, helpful: helpful) } }
                            )
                            .id(message.id)
                        }
                        if let approval = store.pendingApproval {
                            ApprovalCard(approval: approval, isBusy: store.isDeciding || store.isAwaitingReply) { approve in
                                decide(approve, in: store)
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
                            problem(error)
                        }
                    } else if !session.isSubmitting, session.notice == nil, !session.heardNothing {
                        Text("Ask about your training, meals or recovery.")
                            .font(.north(.subheadline))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    if session.heardNothing {
                        Text("Didn't catch that. Type your question or tap the microphone.")
                            .font(.north(.subheadline))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    if let notice = session.notice {
                        problem(notice)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
            // A card that hugs a short answer and scrolls a long one.
            .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in
                messagesHeight = height
            }
            .frame(height: min(messagesHeight, maxHeight))
            .onChange(of: session.store?.messages.last?.text) {
                proxy.scrollTo(bottom, anchor: .bottom)
            }
            .onChange(of: session.store?.pendingApproval) {
                proxy.scrollTo(bottom, anchor: .bottom)
            }
        }
    }

    private func problem(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.bubble")
            .font(.subheadline)
            .foregroundStyle(NorthColor.destructive)
    }

    private var composer: some View {
        @Bindable var session = session
        return ChatComposer(
            text: $session.draft,
            placeholder: "Ask your coach",
            isBusy: session.isSubmitting || session.store?.phase == .replying,
            canSend: session.canSend,
            focused: $composing,
            asksForMicrophone: session.asksForMicrophone,
            onListeningChange: { listening in
                if listening { session.composerStartedListening() }
            },
            onSend: { Task { await session.send() } },
            onStop: { session.stopReply() },
            attachments: { EmptyView() }
        )
    }

    /// Goes on even if the overlay closes meanwhile: the screens underneath
    /// still have to catch up with what the approved tools wrote.
    private func decide(_ approve: Bool, in store: ConversationStore) {
        Task {
            await store.decide(approve: approve)
            if approve { router.dataChanged() }
        }
    }

    private let bottom = "bottom"
}
