import NorthAPI
import SwiftUI

/// The Coach tab: conversations, newest first, and a way to start one.
struct CoachScreen: View {
    @State private var conversations: [ConversationSummary] = []
    @State private var path: [ConversationSummary] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @Environment(\.scenePhase) private var scenePhase

    private let coach: CoachServicing

    init(coach: CoachServicing = CoachService()) {
        self.coach = coach
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && conversations.isEmpty {
                    ProgressView()
                } else if conversations.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Conversation", systemImage: "bubble.left") { Task { await start(reflection: false) } }
                        Button("New Reflection", systemImage: "sparkles") { Task { await start(reflection: true) } }
                    } label: {
                        Label("New", systemImage: "square.and.pencil")
                    } primaryAction: {
                        Task { await start(reflection: false) }
                    }
                    .accessibilityIdentifier("new-conversation")
                    .anchorGuidedTour(.coach)
                }
            }
            .navigationDestination(for: ConversationSummary.self) { summary in
                ConversationView(summary: summary, coach: coach)
            }
            .refreshable { await load() }
            .alert("Coach unavailable", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(loadError ?? "")
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private var list: some View {
        List {
            ForEach(conversations, id: \.id) { conversation in
                NavigationLink(value: conversation) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text(conversation.title)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: conversation.kind == .reflection ? "sparkles" : "bubble.left")
                        }
                        Text(conversation.updatedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { conversations[$0] }
                conversations.remove(atOffsets: offsets)
                Task {
                    for conversation in doomed {
                        try? await coach.delete(conversation.id)
                    }
                }
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Talk to your coach", systemImage: "bubble.left.and.text.bubble.right")
        } description: {
            Text("Ask about training, a goal, or how your week went. The same coach answers on the web and in Telegram.")
        } actions: {
            Button("Start a Conversation") { Task { await start(reflection: false) } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            conversations = try await coach.conversations()
        } catch {
            if conversations.isEmpty { loadError = error.localizedDescription }
        }
    }

    private func start(reflection: Bool) async {
        do {
            let conversation = try await coach.start(reflection: reflection)
            conversations.insert(conversation, at: 0)
            path = [conversation]
        } catch {
            loadError = error.localizedDescription
        }
    }
}
