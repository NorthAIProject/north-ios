import NorthKit
import SwiftUI

/// Khepri's mark floating over Today. A tap opens the Coach tab; a hold opens
/// the quick coach and listens until the finger comes up.
struct CoachOrb: View {
    let onTap: () -> Void
    let onHoldBegan: () -> Void
    let onHoldEnded: () -> Void
    /// VoiceOver cannot hold-and-speak, so it gets a way in for typing.
    let onAskByTyping: () -> Void

    /// Long enough that a tap never opens the microphone.
    private static let holdThreshold: Duration = .milliseconds(350)
    /// A finger that slid this far was not tapping.
    private static let tapSlop: CGFloat = 12
    private static let size: CGFloat = 60

    // Resets when a gesture is cancelled as well as when it ends. `onEnded` does
    // not run on a cancel (a call, Control Center), which would leave the
    // microphone on. It can't be the only signal: a quick tap begins and ends
    // within one update, so it is never seen to change.
    @GestureState private var touching = false
    @State private var pressed = false
    @State private var slid = false
    @State private var holding = false
    @State private var holdTimer: Task<Void, Never>?
    @AppStorage("quickCoach.hasHeld") private var hasHeld = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if !hasHeld {
                Text("Hold to ask")
                    .font(.north(.footnote).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            orb
        }
    }

    private var orb: some View {
        // The mark carries fixed brand colour; never tint it.
        NorthBrand.mark
            .resizable()
            .scaledToFit()
            .padding(10)
            .frame(width: Self.size, height: Self.size)
            .background(.regularMaterial, in: Circle())
            .overlay { Circle().strokeBorder(NorthColor.agent.opacity(0.6), lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .contentShape(Circle())
            .scaleEffect(touching && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.4), value: touching)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        if !pressed { touchBegan() }
                        if abs(value.translation.width) > Self.tapSlop || abs(value.translation.height) > Self.tapSlop {
                            slid = true
                        }
                    }
                    .onEnded { _ in touchEnded() }
            )
            .onChange(of: touching) { _, touching in
                if !touching { touchEnded() }
            }
            .onDisappear { touchEnded() }
            .accessibilityElement()
            .accessibilityLabel("Coach")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Ask your coach") { onAskByTyping() }
            .accessibilityIdentifier("coach-orb")
    }

    private func touchBegan() {
        pressed = true
        slid = false
        holdTimer = Task {
            guard (try? await Task.sleep(for: Self.holdThreshold)) != nil else { return }
            holding = true
            hasHeld = true
            onHoldBegan()
        }
    }

    private func touchEnded() {
        guard pressed else { return }
        pressed = false
        holdTimer?.cancel()
        holdTimer = nil
        if holding {
            holding = false
            onHoldEnded()
        } else if !slid {
            onTap()
        }
    }
}
