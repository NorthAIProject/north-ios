import NorthAPI
import NorthKit
import SwiftUI

/// A badge just earned: the coin turns in, then what it is for. Several badges
/// page inside this one cover. Nothing here is a loss warning or an XP count.
struct UnlockCelebrationView: View {
    let awards: [Award]
    /// Called when a badge's page is the one in front.
    let onShown: (String) -> Void
    let onViewProfile: () -> Void
    let onDone: () -> Void

    @State private var selected: String?
    @State private var shown: [Award] = []

    init(awards: [Award], onShown: @escaping (String) -> Void,
         onViewProfile: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.awards = awards
        self.onShown = onShown
        self.onViewProfile = onViewProfile
        self.onDone = onDone
        _shown = State(initialValue: awards)
        _selected = State(initialValue: awards.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selected) {
                ForEach(shown) { award in
                    UnlockPage(award: award, isCurrent: selected == award.id, onShown: onShown)
                        .tag(Optional(award.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: shown.count > 1 ? .always : .never))
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
        // The queue empties as soon as Done is pressed, while the cover is still
        // sliding away, so what it pages through is kept here: new arrivals join,
        // nothing leaves.
        .onChange(of: awards.map(\.id), initial: true) {
            for award in awards where !shown.contains(where: { $0.id == award.id }) { shown.append(award) }
            if selected == nil { selected = shown.first?.id }
        }
    }
}

private struct UnlockPage: View {
    let award: Award
    let isCurrent: Bool
    let onShown: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        // Scrolls, with the content centred when it fits, so large text sizes
        // are not clipped.
        GeometryReader { proxy in
            ScrollView {
                content.frame(minHeight: proxy.size.height)
            }
        }
        .sensoryFeedback(.success, trigger: arrived)
        .onChange(of: isCurrent, initial: true) { _, current in
            guard current else { return }
            arrived = true
            onShown(award.id)
        }
    }

    private var content: some View {
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
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
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
