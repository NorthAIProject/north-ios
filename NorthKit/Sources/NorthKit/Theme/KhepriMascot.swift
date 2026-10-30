#if canImport(UIKit)
import SwiftUI

/// Khepri, the robotic scarab companion of the 2026-10-30 brand (navy armour,
/// gold trim, a solar core in its chest).
///
/// Only the idle pose is drawn: it is cut from the brand reference image. The
/// other moods are the same art moved and lit differently. Distinct poses are
/// tracked as follow-up work; when one lands, map its mood in `image`.
///
/// Motion is a slow hover and a pulse of warm light. Both stop under Reduce
/// Motion. The view is decorative: every surface it appears on already says
/// what is happening.
public struct KhepriMascot: View {
    public enum Mood: Sendable, CaseIterable {
        case idle, listening, thinking, success, encouragement, notification, error, sleeping
    }

    private let mood: Mood
    private let hovers: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter hovers: the idle float. Off for small, repeated placements
    ///   such as a list row, where steady motion would distract.
    public init(_ mood: Mood = .idle, hovers: Bool = true) {
        self.mood = mood
        self.hovers = hovers
    }

    public var body: some View {
        image
            .resizable()
            .scaledToFit()
            .rotationEffect(tilt, anchor: .bottom)
            .saturation(mood == .error ? 0.35 : 1)
            .brightness(dimming)
            // Without a trigger the phases cycle for as long as the view is on
            // screen; one phase means it holds still.
            .phaseAnimator(animates ? MascotPhase.allCases : [.rest]) { content, phase in
                content
                    .offset(y: phase.lift)
                    .shadow(color: Self.solarCore.opacity(phase.glow * glowStrength), radius: 14)
            } animation: { _ in
                .easeInOut(duration: 3)
            }
            .accessibilityHidden(true)
    }

    private var image: Image { Image("KhepriMascotIdle", bundle: .module) }

    private var animates: Bool { hovers && !reduceMotion && mood != .sleeping }

    private var tilt: Angle {
        switch mood {
        case .thinking: .degrees(-6)
        case .listening: .degrees(-3)
        case .encouragement: .degrees(4)
        case .error: .degrees(-2)
        default: .zero
        }
    }

    private var dimming: Double {
        switch mood {
        case .sleeping: -0.18
        case .error: -0.1
        default: 0
        }
    }

    private var glowStrength: Double {
        switch mood {
        case .success, .notification: 0.55
        case .listening, .thinking: 0.35
        case .sleeping, .error: 0
        default: 0.2
        }
    }

    /// Solar Core, #FFE0A1.
    private static let solarCore = Color(red: 1, green: 0.878, blue: 0.631)
}

private enum MascotPhase: CaseIterable {
    case rest, rise

    var lift: CGFloat { self == .rise ? -4 : 0 }
    var glow: Double { self == .rise ? 1 : 0.55 }
}

#Preview("Moods") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) {
        ForEach(KhepriMascot.Mood.allCases, id: \.self) { mood in
            VStack {
                KhepriMascot(mood).frame(width: 96, height: 96)
                Text(String(describing: mood)).font(.caption)
            }
        }
    }
    .padding()
}
#endif
