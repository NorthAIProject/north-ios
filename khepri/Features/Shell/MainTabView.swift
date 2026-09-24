import NorthAPI
import SwiftUI

/// The signed-in app: five tabs, each with its own navigation stack.
struct MainTabView: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @Environment(GuidedTour.self) private var tour

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Today", systemImage: "sun.horizon", value: AppTab.today) {
                TodayScreen()
            }
            Tab("Coach", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.coach) {
                CoachScreen()
            }
            Tab("Training", systemImage: "figure.strengthtraining.traditional", value: AppTab.training) {
                PlaceholderScreen(title: "Training", systemImage: "figure.strengthtraining.traditional", phase: 3,
                                  summary: "Plans, workouts, the exercise library and reminders before you train.",
                                  tourStep: .training)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                PlaceholderScreen(title: "Progress", systemImage: "chart.line.uptrend.xyaxis", phase: 4,
                                  summary: "Insights across body, mind and training, with Apple Health and Strava.")
            }
            Tab("More", systemImage: "square.grid.2x2", value: AppTab.more) {
                MoreScreen(user: user)
            }
        }
        .guidedTourOverlay(tour, router: router)
        .onAppear { tour.startIfNeeded() }
    }
}

/// Stands in for a tab that a later phase builds, so internal TestFlight
/// builds show the whole shape of the app and say what is coming.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let phase: Int
    let summary: String
    var tourStep: TourStep?

    /// Wraps the content in its own navigation stack, for use as a tab root.
    /// Pushed from a list, use `content` so stacks do not nest.
    var body: some View {
        NavigationStack { content }
    }

    var content: some View {
        // Hand-built rather than ContentUnavailableView: an anchor inside that
        // view's label never reaches the tour overlay.
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Arrives in phase \(phase)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(24)
        .modifier(OptionalTourAnchor(step: tourStep))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

private struct OptionalTourAnchor: ViewModifier {
    let step: TourStep?

    func body(content: Content) -> some View {
        if let step {
            content.anchorGuidedTour(step)
        } else {
            content
        }
    }
}
