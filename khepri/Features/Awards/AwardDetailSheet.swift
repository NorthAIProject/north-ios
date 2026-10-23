import NorthAPI
import NorthKit
import SwiftUI

/// One badge, large: what it is for, when it was earned or how far along it is.
/// Used from the awards screen, a profile's strip and the feed.
struct AwardDetailSheet: View {
    let award: Award
    @Environment(\.dismiss) private var dismiss

    private var isEarned: Bool { award.earnedAt != nil }

    var body: some View {
        ScrollView { content }
    }

    private var content: some View {
        VStack(spacing: 14) {
            CoinMedalView(badgeID: award.id, area: award.area, size: 160, locked: !isEarned)
                .padding(.top, 24)
                .accessibilityHidden(true)
            Text(award.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(award.description).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let earnedAt = award.earnedAt {
                Text("Earned \(earnedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
            } else {
                VStack(spacing: 4) {
                    ProgressView(value: fraction)
                    Text("\(award.progress ?? 0) of \(award.target)")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            }
            if let rarity = award.rarity, !rarity.isEmpty {
                Text("Earned by \(rarity) of Khepri members")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(NorthColor.signal)
        }
        .padding()
        .accessibilityElement(children: .contain)
    }

    private var fraction: Double {
        guard award.target > 0 else { return 0 }
        return min(1, max(0, Double(award.progress ?? 0) / Double(award.target)))
    }
}
