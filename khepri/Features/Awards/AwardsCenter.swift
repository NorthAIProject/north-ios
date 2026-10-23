import Foundation
import NorthAPI
import Observation

/// Badges earned and not yet celebrated, and the one place that says a badge
/// was celebrated. A badge is told to the server only once the person has seen
/// it, so no other device repeats the moment.
@MainActor
@Observable
final class AwardsCenter {
    /// What the celebration is showing, in the order it was earned.
    private(set) var pending: [Award] = []

    private let service: AwardsServicing
    /// Ids the person has been shown, whether or not the server has taken
    /// the mark yet.
    private var viewed: Set<String> = []
    /// Badges celebrated in this session. Never shrinks until `reset()`, so a
    /// refresh that was answered before a dismiss finished cannot bring one back.
    private var celebrated: Set<String> = []
    /// Celebrated badges whose mark-seen the server has not taken yet, tried
    /// again on every refresh and dismiss.
    private var owed: [String] = []
    /// Bumped by `reset()`; an answer fetched under an older one is dropped.
    private var generation = 0

    init(service: AwardsServicing = AwardsService()) {
        self.service = service
    }

    /// The celebration put this badge on screen.
    func didShow(_ id: String) {
        if pending.contains(where: { $0.id == id }) { viewed.insert(id) }
    }

    /// Asks the server what is unseen and queues what is new. A failed call
    /// changes nothing: the next refresh asks again.
    func refresh() async {
        let started = generation
        await settleOwed()
        guard started == generation, let unseen = try? await service.unseen(), started == generation else { return }
        for award in unseen where !celebrated.contains(award.id) && !pending.contains(where: { $0.id == award.id }) {
            pending.append(award)
        }
    }

    /// The celebration closed: what it showed is seen. A badge that joined
    /// while it was up and was never on screen stays queued for the next time.
    func dismiss() async {
        let shown = pending.filter { viewed.contains($0.id) }.map(\.id)
        pending.removeAll { viewed.contains($0.id) }
        celebrated.formUnion(shown)
        owed.append(contentsOf: shown.filter { !owed.contains($0) })
        await settleOwed()
    }

    /// Forgets everything, for when somebody else signs in.
    func reset() {
        generation += 1
        pending = []
        viewed = []
        celebrated = []
        owed = []
    }

    /// Tells the server what was celebrated. Stops the moment `reset()` runs,
    /// so the last account's ids are never sent under the next account's session.
    private func settleOwed() async {
        let started = generation
        for id in owed {
            guard started == generation else { return }
            do {
                try await service.markSeen(id)
            } catch {
                continue
            }
            guard started == generation else { return }
            owed.removeAll { $0 == id }
        }
    }
}
