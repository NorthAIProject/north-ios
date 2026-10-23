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
    /// Badges already celebrated here whose mark-seen the server has not
    /// taken yet. They are tried again on every refresh, and kept out of
    /// `pending` meanwhile, since the server still lists them as unseen.
    private var owed: [String] = []

    init(service: AwardsServicing = AwardsService()) {
        self.service = service
    }

    /// Asks the server what is unseen and queues what is new. A failed call
    /// changes nothing: the next refresh asks again.
    func refresh() async {
        await settleOwed()
        guard let unseen = try? await service.unseen() else { return }
        for award in unseen where !owed.contains(award.id) && !pending.contains(where: { $0.id == award.id }) {
            pending.append(award)
        }
    }

    /// The celebration was shown and closed: every badge in it is seen.
    func dismiss() async {
        owed.append(contentsOf: pending.map(\.id).filter { !owed.contains($0) })
        pending = []
        await settleOwed()
    }

    /// Forgets everything, for when somebody else signs in.
    func reset() {
        pending = []
        owed = []
    }

    private func settleOwed() async {
        for id in owed {
            do {
                try await service.markSeen(id)
                owed.removeAll { $0 == id }
            } catch {
                continue
            }
        }
    }
}
