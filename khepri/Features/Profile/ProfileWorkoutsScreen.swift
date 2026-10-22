import NorthAPI
import NorthKit
import SwiftUI

/// Everything somebody finished, newest first, twenty at a time.
struct ProfileWorkoutsScreen: View {
    let handle: String
    let name: String
    var service: ProfileServicing = ProfileService()

    @State private var cards: [WorkoutCard] = []
    @State private var next: Date?
    @State private var shared = true
    @State private var loaded = false
    @State private var error: String?
    @State private var isLoadingMore = false

    var body: some View {
        Group {
            if !loaded, let error {
                ContentUnavailableView {
                    Label("Workouts did not load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if !loaded {
                ProgressView()
            } else {
                list
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Coming back from a workout re-runs this; keep the pages and scroll.
            guard !loaded else { return }
            await load()
        }
        .refreshable { await load() }
    }

    private var list: some View {
        List {
            if !shared {
                Text("Workouts aren't shared.").foregroundStyle(.secondary)
            } else if cards.isEmpty {
                Text("No workouts yet.").foregroundStyle(.secondary)
            }
            ForEach(cards, id: \.sessionId) { card in
                NavigationLink {
                    WorkoutDetailScreen(handle: handle, card: card, authorName: name)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.titleLine).font(.subheadline)
                        WorkoutCardView(card: card)
                    }
                }
            }
            if let error { ErrorRow(error) }
            if next != nil {
                Button("More") { Task { await more() } }
                    .disabled(isLoadingMore)
            }
        }
    }

    private func load() async {
        do {
            let page = try await service.workouts(handle: handle, before: nil)
            cards = page.items
            next = page.before
            shared = page.shared
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func more() async {
        guard let cursor = next else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.workouts(handle: handle, before: cursor)
            cards += page.items
            next = page.before
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
