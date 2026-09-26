import NorthAPI
import SwiftUI

/// The signed-in app: five tabs, each with its own navigation stack.
struct MainTabView: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @Environment(GuidedTour.self) private var tour
    @Environment(\.scenePhase) private var scenePhase

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
                TrainingScreen()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                InsightsScreen()
            }
            Tab("More", systemImage: "square.grid.2x2", value: AppTab.more) {
                MoreScreen(user: user)
            }
        }
        .guidedTourOverlay(tour, router: router)
        .sheet(isPresented: $router.showsCheckInFlow) {
            NavigationStack {
                CheckInsScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { router.showsCheckInFlow = false }
                        }
                    }
            }
        }
        .onAppear { tour.startIfNeeded() }
        // Apple Health catches up whenever the app comes forward; the sync
        // itself decides whether it is on.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task.detached { _ = try? await HealthSync.shared.syncIfEnabled() } }
        }
    }
}
