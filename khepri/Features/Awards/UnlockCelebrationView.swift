import NorthAPI
import NorthKit
import SwiftUI

/// A badge just earned: the coin turns in, then what it is for. Several badges
/// page inside this one cover. Nothing here is a loss warning or an XP count.
struct UnlockCelebrationView: View {
    let awards: [Award]
    let onViewProfile: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ForEach(awards) { award in
                    UnlockPage(award: award)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: awards.count > 1 ? .always : .never))
            VStack(spacing: 8) {
                Button(action: onViewProfile) {
                    Text("View on Profile").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .northProminentButton()
                .controlSize(.large)
                .accessibilityIdentifier("awards.viewProfile")
                Button("Done", action: onDone)
                    .font(.headline)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("awards.done")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
}

private struct UnlockPage: View {
    let award: Award
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text("Award earned")
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            CoinMedalView(badgeID: award.id, area: award.area, size: 200, locked: false)
                .modifier(CoinEntrance(arrived: arrived, reduceMotion: reduceMotion))
                .padding(.vertical, 12)
                .accessibilityHidden(true)
            Text(award.name).font(.title.weight(.semibold)).multilineTextAlignment(.center)
            Text(award.description).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let earnedAt = award.earnedAt {
                Text("Earned \(earnedAt.formatted(date: .abbreviated, time: .omitted))").font(.subheadline)
            }
            if let rarity = award.rarity, !rarity.isEmpty {
                Text("Earned by \(rarity) of Khepri members")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .sensoryFeedback(.success, trigger: arrived)
        .accessibilityElement(children: .combine)
        .onAppear { arrived = true }
    }
}

/// The coin springs in with a slow turn about its vertical axis; with Reduce
/// Motion on it only fades.
private struct CoinEntrance: ViewModifier {
    let arrived: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(arrived ? 1 : 0)
                .animation(.easeIn(duration: 0.4), value: arrived)
        } else {
            content
                .scaleEffect(arrived ? 1 : 0.4)
                .opacity(arrived ? 1 : 0)
                .rotation3DEffect(.degrees(arrived ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .animation(.spring(duration: 1.6, bounce: 0.25), value: arrived)
        }
    }
}
