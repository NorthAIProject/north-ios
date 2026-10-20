import NorthAPI
import NorthKit
import SwiftUI
import UIKit

/// One crew channel: its messages, the sends in flight, and the composer.
/// Built like the coach's `ConversationView`.
struct ChannelView: View {
    let store: CrewChatStore
    let channelName: String
    let role: CrewRole

    @State private var draft = ""
    @State private var loaded = false
    /// The own message being edited in the composer.
    @State private var editing: CrewMessage?
    @State private var reporting: CrewMessage?
    @State private var blocking: CrewMessage?
    @State private var showingRules = false
    @FocusState private var composing: Bool
    @Environment(\.scenePhase) private var scenePhase

    private let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.hasOlder {
                        Button("Load older messages") { Task { await store.loadOlder() } }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    ForEach(store.rows) { message in
                        CrewMessageRow(
                            message: message,
                            actions: CrewMessageActions.available(for: message, meID: store.meID, role: role),
                            onAction: { perform($0, on: message) },
                            onReact: { key in Task { await store.toggle(key, on: message) } }
                        )
                        .id(message.id)
                    }
                    ForEach(store.pending) { item in
                        PendingRow(
                            item: item,
                            waitingForRules: store.needsTerms && !item.failed,
                            onRetry: { Task { await store.retry(item.id) } },
                            onRules: { showingRules = true }
                        )
                        .id(item.id)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.rows.last?.id) {
                proxy.scrollTo(bottom, anchor: .bottom)
                if scenePhase == .active { Task { await store.markRead() } }
            }
            .onChange(of: store.pending.count) {
                withAnimation { proxy.scrollTo(bottom, anchor: .bottom) }
            }
        }
        .overlay {
            if !loaded {
                ProgressView()
            } else if store.rows.isEmpty, store.pending.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Say something to get it going.")
                )
            }
        }
        .overlay(alignment: .top) {
            if let error = store.error {
                CrewErrorBanner(text: error) { store.clearError() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatComposer(
                text: $draft,
                placeholder: "Message #\(channelName)",
                isBusy: false,
                canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                focused: $composing,
                dictation: false,
                onSend: send,
                attachments: { composerBar }
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await store.load()
            loaded = true
            await store.markRead()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await store.markRead() } }
        }
        .sheet(isPresented: $showingRules) {
            CrewRulesSheet {
                showingRules = false
                Task { await store.acceptTermsAndResend() }
            }
        }
        .sheet(item: $reporting) { message in
            CrewReportSheet { reason, note in
                Task { await store.report(message, reason: reason, note: note) }
            }
        }
        .confirmationDialog(
            Text("Block \(blocking?.authorName ?? "")? You won't see each other's messages."),
            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
            titleVisibility: .visible,
            presenting: blocking
        ) { message in
            Button("Block", role: .destructive) {
                Task { await store.block(authorOf: message) }
            }
        }
    }

    /// Replying to someone, or editing your own message, above the field.
    @ViewBuilder private var composerBar: some View {
        if editing != nil {
            ComposerBar(systemImage: "pencil", title: Text("Edit"), cancelLabel: "Cancel") {
                editing = nil
                draft = ""
            }
        } else if let reply = store.replyTo {
            ComposerBar(
                systemImage: "arrowshape.turn.up.left",
                title: Text("Replying to \(reply.authorName)"),
                cancelLabel: "Cancel reply"
            ) {
                store.replyTo = nil
            }
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        if let message = editing {
            editing = nil
            Task { await store.edit(message, body: body) }
            return
        }
        Task {
            await store.send(body)
            // The first post, or a send after the rules were swiped away.
            if store.needsTerms { showingRules = true }
        }
    }

    private func perform(_ action: CrewMessageAction, on message: CrewMessage) {
        switch action {
        case .react:
            break
        case .reply:
            editing = nil
            store.replyTo = message
            composing = true
        case .copy:
            UIPasteboard.general.string = message.body
        case .edit:
            store.replyTo = nil
            editing = message
            draft = message.body ?? ""
            composing = true
        case .pin, .unpin:
            Task { await store.setPinned(message, action == .pin) }
        case .delete:
            Task { await store.delete(message) }
        case .report:
            reporting = message
        case .block:
            blocking = message
        }
    }
}

/// "Replying to …" or "Edit" over the composer, with a way out.
private struct ComposerBar: View {
    let systemImage: String
    let title: Text
    let cancelLabel: LocalizedStringKey
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(NorthColor.signal)
            title.font(.footnote).lineLimit(1)
            Spacer()
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel(cancelLabel)
        }
        .padding(.horizontal, 4)
    }
}

/// A message on its way: dimmed while sending, with Retry once it failed,
/// and a way back to the rules when they stand in its way.
private struct PendingRow: View {
    let item: CrewChatStore.Pending
    let waitingForRules: Bool
    let onRetry: () -> Void
    let onRules: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CrewMessageText(text: item.body)
                .opacity(item.failed ? 1 : 0.5)
            if item.failed {
                Button("Try Again", systemImage: "exclamationmark.circle", action: onRetry)
                    .font(.caption)
                    .foregroundStyle(NorthColor.destructive)
            } else if waitingForRules {
                Button("Accept the crew rules to post.", action: onRules)
                    .font(.caption)
            }
        }
        .padding(.leading, 62)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An error that does not block the screen; the person dismisses it.
struct CrewErrorBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NorthColor.destructive)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: NorthRadius.medium))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
