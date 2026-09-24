import NorthKit
import SwiftUI

/// Collects the frame of each view marked with `anchorGuidedTour(_:)` so one
/// overlay, above the tab bar, can light it up.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourStep: Anchor<CGRect>] = [:]

    static func reduce(value: inout [TourStep: Anchor<CGRect>], nextValue: () -> [TourStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as what the tour highlights for `step`.
    func anchorGuidedTour(_ step: TourStep) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step: $0] }
    }

    /// Dims the screen around the current step's anchor and shows its callout.
    /// Apply once, at the root that contains every anchor (the tab view).
    func guidedTourOverlay(_ tour: GuidedTour, router: AppRouter) -> some View {
        overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if let step = tour.current {
                ZStack(alignment: .bottom) {
                    // The dimming and the anchor must share one coordinate
                    // space: both ignore the safe area, or the cut-out lands
                    // one status bar too high.
                    GeometryReader { proxy in
                        TourDimming(highlight: anchors[step].map { proxy[$0] })
                    }
                    .ignoresSafeArea()

                    TourCallout(
                        step: step,
                        progress: tour.progressLabel ?? "",
                        onNext: { tour.advance() },
                        onSkip: { tour.skip() }
                    )
                    .padding(16)
                    .padding(.bottom, 64) // clear of the tab bar
                }
                .transition(.opacity)
            }
        }
        // Move to the step's tab as it starts, so its anchor exists to find.
        .onChange(of: tour.current) { _, step in
            if let step { router.selectedTab = step.tab }
        }
        .animation(.easeInOut(duration: 0.25), value: tour.current)
    }
}

private struct TourDimming: View {
    let highlight: CGRect?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Canvas { context, size in
            var shape = Path(CGRect(origin: .zero, size: size))
            if let highlight {
                shape.addPath(Path(roundedRect: highlight.insetBy(dx: -8, dy: -8), cornerRadius: 10))
            }
            context.fill(shape, with: .color(.black.opacity(reduceTransparency ? 0.8 : 0.55)), style: FillStyle(eoFill: true))
        }
        // Taps on the dimmed area do nothing: the callout's buttons are the
        // only way on, so nobody skips by accident.
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
    }
}

private struct TourCallout: View {
    let step: TourStep
    let progress: String
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(progress.uppercased())
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(NorthColor.signal)
            Text(step.title)
                .font(.headline)
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Skip tour", action: onSkip)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(step == TourStep.allCases.last ? "Done" : "Next", action: onNext)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onSkip)
    }
}
