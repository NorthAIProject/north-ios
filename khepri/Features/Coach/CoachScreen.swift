import NorthAPI
import NorthKit
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
            ScrollViewReader { proxy in
                Group {
                    if isLoading && conversations.isEmpty {
                        ProgressView()
                    } else if conversations.isEmpty {
                        empty
                    } else {
                        list
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                // Khepri's mark stands where the title was, as in the thread.
                .safeAreaInset(edge: .top, spacing: 0) {
                    CoachHeader(
                        activity: isLoading && conversations.isEmpty ? .catchingUp : .ready,
                        canvas: Color(.systemGroupedBackground),
                        anchorsTour: true,
                        onLeading: {
                            guard let first = conversations.first else { return }
                            withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                        },
                        onNew: { reflection in Task { await start(reflection: reflection) } }
                    )
                }
            }
            .navigationTitle("Coach")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: ConversationSummary.self) { summary in
                ConversationView(summary: summary, coach: coach) { reflection in
                    Task { await start(reflection: reflection) }
                }
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
                                .foregroundStyle(NorthColor.agent)
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
        // No icon: the header's mark already says who is listening.
        ContentUnavailableView {
            Text("Talk to your coach")
        } description: {
            Text("Ask about training, a goal, or how your week went. The same coach answers on the web and in Telegram.")
        } actions: {
            Button("Start a Conversation") { Task { await start(reflection: false) } }
                .northProminentButton()
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
