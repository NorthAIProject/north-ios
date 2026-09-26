import NorthKit
import SwiftUI
import UIKit

/// The coach's header, after Loci's Muse chat: Khepri's mark in a circle, a
/// pill naming it and saying what it is doing, a circle button on the left
/// and a "New chat" pill on the right.
///
/// Place it with `.safeAreaInset(edge: .top, spacing: 0)` so the conversation
/// scrolls under it; it draws its own scrim, so it needs no blur.
struct CoachHeader: View {
    var activity: CoachActivity = .ready
    /// The colour of the screen underneath, which the scrim fades from.
    var canvas: Color = Color(.systemBackground)
    var leadingSystemImage = "list.bullet"
    var leadingLabel = "Conversations"
    var newIdentifier = "new-conversation"
    /// Whether the guided tour's Coach step points at "New chat". Only the
    /// list's header does, so a pushed thread never offers a second anchor.
    var anchorsTour = false
    var onLeading: () -> Void = {}
    var onNew: (_ reflection: Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: onLeading) {
                    Image(systemName: leadingSystemImage)
                        .font(.body.weight(.semibold))
                        .frame(width: CoachHeaderMetrics.buttonSize, height: CoachHeaderMetrics.buttonSize)
                        .background(CoachHeaderMetrics.pill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(leadingLabel)

                Spacer()

                Menu {
                    Button("New Conversation", systemImage: "bubble.left") { onNew(false) }
                    Button("New Reflection", systemImage: "sparkles") { onNew(true) }
                } label: {
                    Text("New chat")
                        .font(.north(.subheadline).weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: CoachHeaderMetrics.buttonSize)
                        .background(CoachHeaderMetrics.pill, in: Capsule())
                        .contentShape(Capsule())
                } primaryAction: {
                    onNew(false)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityIdentifier(newIdentifier)
                .anchorPreference(key: TourAnchorKey.self, value: .bounds) { anchorsTour ? [.coach: $0] : [:] }
            }
            .frame(height: 56)
            .padding(.horizontal, 16)

            VStack(spacing: 8) {
                CoachAvatar(mood: activity.mood)
                identity
            }
            .padding(.horizontal, 64)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { CoachScrim(canvas: canvas).ignoresSafeArea(edges: .top) }
    }

    private var identity: some View {
        VStack(spacing: 1) {
            Text(NorthBrand.name)
                .font(.north(.subheadline).weight(.semibold))
            Text(activity.status)
                .font(.north(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activity.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(CoachHeaderMetrics.pill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("coach-header")
    }
}

enum CoachHeaderMetrics {
    static let avatarSize: CGFloat = 110
    static let buttonSize: CGFloat = 40
    static let scrimHeight: CGFloat = 120
    static let ringWidth: CGFloat = 3
    static let ringInset: CGFloat = 5
    /// Pills, the circle button and the avatar's plate: a fill that reads on
    /// both the plain and the grouped background.
    static let pill = Color(.secondarySystemFill)
}

/// Khepri's mark: the same art in every state, with a ring for the mood. It
/// never floats or bobs; finishing a reply earns one small pop.
struct CoachAvatar: View {
    var mood: CoachMood = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1

    var body: some View {
        // The mark carries fixed brand colour; never tint it.
        NorthBrand.mark
            .resizable()
            .scaledToFit()
            .padding(20)
            .frame(width: CoachHeaderMetrics.avatarSize, height: CoachHeaderMetrics.avatarSize)
            .background(CoachHeaderMetrics.pill, in: Circle())
            .clipShape(Circle())
            .overlay { CoachRing(mood: mood).padding(-CoachHeaderMetrics.ringInset) }
            .scaleEffect(pop)
            .onChange(of: mood) { _, new in
                guard new == .celebrating, !reduceMotion else { return }
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) { pop = 1.06 } completion: {
                    withAnimation(.spring(duration: 0.3, bounce: 0.4)) { pop = 1 }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The ring around the mark. Working: an arc going round (a full static ring
/// under Reduce Motion). Listening: a faint full ring. Celebrating: a full
/// ring. Idle: none. In the coach's colour, as everything the coach does is.
struct CoachRing: View {
    let mood: CoachMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch mood {
            case .idle:
                EmptyView()
            case .listening:
                Circle().stroke(NorthColor.agent.opacity(0.45), lineWidth: CoachHeaderMetrics.ringWidth)
            case .celebrating:
                Circle().stroke(NorthColor.agent, lineWidth: CoachHeaderMetrics.ringWidth)
            case .working:
                if reduceMotion {
                    Circle().stroke(NorthColor.agent, lineWidth: CoachHeaderMetrics.ringWidth)
                } else {
                    spinningArc
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mood)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One turn every 1.4s, driven by the frame clock so it never snaps back.
    private var spinningArc: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Circle().stroke(NorthColor.agent.opacity(0.18), lineWidth: CoachHeaderMetrics.ringWidth)
                Circle()
                    .trim(from: 0, to: 0.32)
                    .stroke(
                        AngularGradient(colors: [NorthColor.agent.opacity(0), NorthColor.agent], center: .center, startAngle: .degrees(0), endAngle: .degrees(115)),
                        style: StrokeStyle(lineWidth: CoachHeaderMetrics.ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(turn * 360))
            }
        }
        .transition(.opacity)
    }
}

/// Solid canvas under the status bar, then a fade to clear, so what scrolls
/// under the header fades out without a blur.
struct CoachScrim: View {
    let canvas: Color

    var body: some View {
        VStack(spacing: 0) {
            canvas
            LinearGradient(colors: [canvas, canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: CoachHeaderMetrics.scrimHeight)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Holds the flash a reply earns when it ends, then clears it after its
    /// duration so the header settles on Ready.
    func coachFlash(_ flash: Binding<CoachActivity.Flash?>) -> some View {
        task(id: flash.wrappedValue) {
            guard let current = flash.wrappedValue else { return }
            try? await Task.sleep(for: current.duration)
            if !Task.isCancelled, flash.wrappedValue == current { flash.wrappedValue = nil }
        }
    }

    /// Keeps the edge swipe back working on a pushed page that hides the
    /// navigation bar. UIKit's own delegate refuses the gesture while the bar
    /// is hidden; this hands it one that allows it whenever there is a page to
    /// go back to.
    func interactivePopEnabled() -> some View {
        background { InteractivePop().frame(width: 0, height: 0).accessibilityHidden(true) }
    }
}

private struct InteractivePop: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ probe: Probe, context: Context) { probe.enable() }

    /// A zero-size view that finds the navigation controller it sits in once
    /// it is on screen.
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            enable()
            // SwiftUI finishes the push after the view joins the window;
            // check again once it has.
            DispatchQueue.main.async { [weak self] in self?.enable() }
        }

        func enable() {
            guard window != nil, let navigation = navigationController else { return }
            PopGestureDelegate.shared.attach(to: navigation)
        }

        private var navigationController: UINavigationController? {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let navigation = next as? UINavigationController { return navigation }
                if let controller = next as? UIViewController, let navigation = controller.navigationController { return navigation }
                responder = next
            }
            return nil
        }
    }
}

/// One delegate for every stack: the gesture holds its delegate weakly, so it
/// lives here. Pages that show the bar keep UIKit's own answer; only a hidden
/// bar gets the override.
private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureDelegate()
    /// Each stack's own delegate, kept strongly so UIKit's answer is still
    /// there to ask.
    private let original = NSMapTable<UINavigationController, AnyObject>.weakToStrongObjects()

    func attach(to navigation: UINavigationController) {
        guard let gesture = navigation.interactivePopGestureRecognizer else { return }
        if gesture.delegate !== self {
            if let existing = gesture.delegate { original.setObject(existing, forKey: navigation) }
            gesture.delegate = self
        }
        gesture.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation = gestureRecognizer.view?.next as? UINavigationController
            ?? original.keyEnumerator().allObjects.lazy.compactMap({ $0 as? UINavigationController })
                .first(where: { $0.interactivePopGestureRecognizer === gestureRecognizer })
        else { return false }
        if !navigation.isNavigationBarHidden, let uikit = original.object(forKey: navigation) as? UIGestureRecognizerDelegate {
            return uikit.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
        }
        // Never mid-transition, and only with somewhere to go back to.
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}

#Preview("Header — states") {
    ScrollView {
        VStack(spacing: 24) {
            CoachHeader(activity: .ready)
            CoachHeader(activity: .resolve(phase: .replying))
            CoachHeader(activity: .resolve(phase: .replying, hasReplyText: true))
            CoachHeader(activity: .resolve(phase: .ready, isListening: true))
            CoachHeader(activity: .resolve(phase: .ready, flash: .done))
            CoachHeader(activity: .resolve(phase: .ready, awaitingApproval: true))
        }
    }
}
