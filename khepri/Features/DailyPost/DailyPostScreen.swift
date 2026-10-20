import NorthAPI
import NorthKit
import SwiftUI

/// The daily post: one short read on training, food, sleep or wellbeing,
/// written by AI once a day and the same for everyone. Today's on top, the
/// ones before it below.
struct DailyPostScreen: View {
    @State private var posts: DailyPosts?
    @State private var loadError: String?
    @Environment(AppRouter.self) private var router

    private let service: DailyPostServicing

    init(service: DailyPostServicing = DailyPostService()) {
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let posts {
                    if let today = posts.today {
                        PostCard(post: today, isToday: true, toggleKudos: { toggle(today) }, ask: {
                            router.open(.askCoach(today.coachDraft))
                        })
                    } else {
                        ContentUnavailableView(
                            "No post yet today",
                            systemImage: "newspaper",
                            description: Text("Today's post is still being written. Check back a little later.")
                        )
                    }
                    if !posts.earlier.isEmpty {
                        Text("Earlier posts")
                            .font(.north(.footnote))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, 8)
                        ForEach(posts.earlier, id: \.id) { post in
                            PostCard(post: post, isToday: false, toggleKudos: { toggle(post) }, ask: nil)
                        }
                    }
                    Text("Written by AI and reviewed automatically before it is posted. Posts are written in English. Not medical advice: for anything persistent, see a doctor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let loadError {
                    ContentUnavailableView("Couldn't load the daily post", systemImage: "wifi.exclamationmark", description: Text(loadError))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Daily Post")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            posts = try await service.posts()
            loadError = nil
        } catch {
            if posts == nil { loadError = error.localizedDescription }
        }
    }

    /// Flips kudos at once and puts it back if the server refuses.
    private func toggle(_ post: DailyPost) {
        let given = !post.kudoed
        replace(post.withKudos(given))
        Task {
            do {
                if given { try await service.giveKudos(post.id) } else { try await service.takeKudos(post.id) }
            } catch {
                replace(post)
            }
        }
    }

    private func replace(_ post: DailyPost) {
        guard var current = posts else { return }
        if current.today?.id == post.id { current.today = post }
        current.earlier = current.earlier.map { $0.id == post.id ? post : $0 }
        posts = current
    }
}

/// One post: the day, the AI badge, the title, the body, and what to do
/// with it.
private struct PostCard: View {
    let post: DailyPost
    let isToday: Bool
    let toggleKudos: () -> Void
    /// Nil for earlier posts: asking the coach is about today's.
    let ask: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(post.day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if post.aiGenerated {
                    Label("AI-written", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("Written by AI")
                }
            }
            Text(post.title)
                .font(isToday ? .north(.title3) : .north(.headline))
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(post.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(isToday ? .body : .subheadline)
                    .foregroundStyle(isToday ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(action: toggleKudos) {
                    Label(post.kudos > 0 ? "\(post.kudos)" : String(localized: "Kudos"), systemImage: post.kudoed ? "hands.clap.fill" : "hands.clap")
                        .font(.subheadline.monospacedDigit())
                }
                .buttonStyle(.bordered)
                .tint(post.kudoed ? NorthColor.signal : .secondary)
                .accessibilityLabel(post.kudoed ? Text("Take back kudos") : Text("Give kudos"))
                .sensoryFeedback(.success, trigger: post.kudoed) { _, given in given }
                if let ask {
                    Button(action: ask) {
                        Label("Ask the Coach About This", systemImage: "bubble.left")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("daily-post-ask-coach")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .northSurfaceCard(padding: 16)
    }
}
