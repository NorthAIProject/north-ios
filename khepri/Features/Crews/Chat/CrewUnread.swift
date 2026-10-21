import Foundation
import NorthAPI
import Observation
import os

/// Unread crew messages, for the badges on the More tab, the Crews row and
/// each crew. The server is the only source: this refreshes from it when the
/// app comes forward, when a crew push arrives while it is open, and when a
/// crew's space closes. Otherwise it only forgets: a crew you were removed
/// from, or everything on sign-out.
@Observable
final class CrewUnread {
    private(set) var total = 0
    private(set) var byCrew: [String: (unread: Int, mentions: Int)] = [:]

    @ObservationIgnored private let service: CrewChatServicing
    /// Counts refreshes, so a slow answer never overwrites a newer one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "crews")

    init(service: CrewChatServicing = CrewChatService()) {
        self.service = service
    }

    /// The unread count of one crew; 0 hides its badge.
    func count(for crewID: String) -> Int {
        byCrew[crewID.lowercased()]?.unread ?? 0
    }

    /// Asks the server (`GET /crews/unread`). A failure keeps the counts as they were.
    func refresh() async {
        generation += 1
        let mine = generation
        do {
            let list = try await service.unread()
            guard mine == generation else { return }
            byCrew = Dictionary(
                list.crews.map { ($0.crewId.lowercased(), (unread: $0.unread ?? 0, mentions: $0.mentions ?? 0)) },
                uniquingKeysWith: { first, _ in first }
            )
            total = list.total
        } catch {
            log.error("crews: unread not refreshed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forgets every count: nobody is signed in, and the next person's
    /// counts are their own. An answer still on its way is dropped.
    func reset() {
        generation += 1
        byCrew = [:]
        total = 0
    }

    /// Forgets a crew you are no longer in, so its messages stop counting.
    func clear(crewID: String) {
        // A refresh already on its way may still count the crew.
        generation += 1
        guard let counts = byCrew.removeValue(forKey: crewID.lowercased()) else { return }
        total = max(0, total - counts.unread)
    }
}
