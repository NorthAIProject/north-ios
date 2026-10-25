import NorthAPI
import NorthKit
import SwiftUI

/// This month's challenge: the coin (locked until met), the title and goal,
/// and how far along you are. Title, goal and progress text arrive localised
/// from the server and are shown as they are.
struct MonthlyChallengeCard: View {
    let challenge: Components.Schemas.MonthlyChallengeView
    var coinSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MonthlyCoinView(month: challenge.month, target: challenge.target, size: coinSize, locked: !challenge.met)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(challenge.title).font(.body.weight(.medium))
                Text(challenge.goal).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Self.fraction(progress: challenge.progress, target: challenge.target))
                if challenge.met {
                    Text("Challenge met")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NorthColor.signal)
                } else {
                    Text(challenge.progressText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monthlyChallenge.card")
    }

    /// Progress as a share of the target, kept inside the bar.
    static func fraction(progress: Int, target: Int) -> Double {
        min(1, max(0, Double(progress) / Double(max(target, 1))))
    }
}
