import Foundation
import NorthAPI

/// What the awards screen shows, decided from the two responses alone.
struct AwardsModel: Equatable {
    typealias MonthlyChallenge = Components.Schemas.MonthlyChallengeView

    struct Row: Equatable, Identifiable {
        let award: Award
        /// Earned and not yet celebrated on any device.
        let isNew: Bool
        var id: String { award.id }
        var isEarned: Bool { award.earnedAt != nil }

        /// How far along a badge still to earn is, 0...1.
        var fraction: Double {
            guard !isEarned, award.target > 0 else { return 0 }
            return min(1, max(0, Double(award.progress ?? 0) / Double(award.target)))
        }

        /// "12 of 30" for a badge still to earn.
        var progressText: String? {
            isEarned ? nil : String(localized: "\(award.progress ?? 0) of \(award.target)")
        }
    }

    /// Earned badges, newest first.
    let earned: [Row]
    /// Badges still to earn, the nearest first.
    let locked: [Row]

    /// The current month's challenge, when the server sent one.
    let challenge: MonthlyChallenge?

    /// Earned badges; monthly medals are not counted in "N of M".
    var badgesEarned: Int { earned.count(where: { $0.award.monthly == nil }) }
    var total: Int { badgesEarned + locked.count }

    init(_ overview: AwardsOverview, unseen: [Award] = []) {
        challenge = overview.monthlyChallenge
        let fresh = Set(unseen.map(\.id))
        earned = overview.earned
            .sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
            .map { Row(award: $0, isNew: fresh.contains($0.id)) }
        locked = overview.locked
            .map { Row(award: $0, isNew: false) }
            .sorted { $0.fraction > $1.fraction }
    }
}
