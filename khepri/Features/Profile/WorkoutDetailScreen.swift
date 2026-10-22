import NorthAPI
import NorthKit
import SwiftUI

/// One workout with every exercise. Opens with the card it was tapped from
/// (two exercises) and fills in the rest from the server.
struct WorkoutDetailScreen: View {
    let handle: String
    let authorName: String
    var service: ProfileServicing = ProfileService()

    @State private var card: WorkoutCard
    @State private var error: String?

    init(handle: String, card: WorkoutCard, authorName: String, service: ProfileServicing = ProfileService()) {
        self.handle = handle
        self.authorName = authorName
        self.service = service
        _card = State(initialValue: card)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name).font(.title2.weight(.medium))
                    Text("\(authorName) · \(card.endedAt.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    let stats = WorkoutCardFormat.stats(card)
                    if !stats.isEmpty {
                        Text(stats.joined(separator: " · "))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let error { Section { ErrorRow(error) } }
            if !card.exercises.isEmpty {
                Section {
                    ForEach(Array(card.exercises.enumerated()), id: \.offset) { _, exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).font(.body.weight(.medium))
                                let detail = WorkoutCardFormat.detail(exercise)
                                if !detail.isEmpty {
                                    Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if exercise.pr { PRBadge(text: String(localized: "PR")) }
                        }
                    }
                }
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            card = try await service.workout(handle: handle, sessionID: card.sessionId)
            error = nil
        } catch {
            // The card we opened with is still worth showing.
            self.error = error.localizedDescription
        }
    }
}
