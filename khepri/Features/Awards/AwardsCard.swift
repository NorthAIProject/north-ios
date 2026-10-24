import NorthAPI
import NorthKit
import SwiftUI

/// The Progress tab's awards: how many are earned and the latest three coins.
struct AwardsCard: View {
    var service: AwardsServicing = AwardsService()
    @Environment(AppRouter.self) private var router
    @State private var overview: AwardsOverview?

    var body: some View {
        Section("Awards") {
            NavigationLink {
                OwnAwardsDestination()
            } label: {
                if let overview {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            let badges = overview.earned.count(where: { $0.monthly == nil })
                            Text("Earned · \(badges) of \(badges + overview.locked.count)")
                            if overview.earned.isEmpty {
                                Text("Finish a workout, check in or hit a goal, and your first badge lands here.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        ForEach(AwardsCard.latest(overview.earned)) { award in
                            AwardCoin(award: award, size: 36)
                        }
                    }
                } else {
                    Text("Awards")
                }
            }
            .accessibilityIdentifier("awards.card")
            if let challenge = overview?.monthlyChallenge {
                MonthlyChallengeCard(challenge: challenge, coinSize: 40)
            }
        }
        .task(id: router.dataVersion) { overview = try? await service.awards() }
    }

    /// The three most recently earned.
    static func latest(_ earned: [Award]) -> [Award] {
        Array(earned.sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }.prefix(3))
    }
}

/// Your own profile when you have a handle, the awards screen when not.
struct OwnAwardsDestination: View {
    var friends: FriendsServicing = FriendsService()
    @State private var handle: String?
    @State private var resolved = false

    var body: some View {
        Group {
            if !resolved {
                ProgressView()
            } else if let handle {
                ProfileScreen(handle: handle)
            } else {
                AwardsScreen()
            }
        }
        .task {
            let found = try? await friends.overview().handle
            handle = (found?.isEmpty == false) ? found : nil
            resolved = true
        }
    }
}
