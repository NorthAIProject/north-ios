import NorthAPI
import SwiftUI

/// The signed-in app: five tabs, each with its own navigation stack.
struct MainTabView: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @Environment(GuidedTour.self) private var tour
    @Environment(\.scenePhase) private var scenePhase
    /// A workout the app was killed during, picked up where it was.
    @State private var resumedWorkout: WorkoutSession?

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
        .sheet(isPresented: $router.showsWeeklyReview) {
            WeeklyReviewFlow()
        }
        // An exercise from Spotlight or Siri, over whatever tab is open.
        .sheet(item: Binding(
            get: { router.openExercise.map(ExerciseSlugRoute.init(slug:)) },
            set: { router.openExercise = $0?.slug }
        )) { route in
            ExerciseSheet(slug: route.slug)
        }
        .fullScreenCover(item: $resumedWorkout) { session in WorkoutSessionView(session: session) }
        .onAppear { tour.startIfNeeded() }
        .task { resumedWorkout = WorkoutSession.resumingKilledWorkout() }
        // Apple Health catches up whenever the app comes forward, and
        // Spotlight's copy of exercises and goals with it; each decides for
        // itself whether there is anything to do. A workout Live Activity with
        // no workout behind it (one stopped on the web, say) ends here too;
        // one a killed workout left is kept for the resumed workout.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                WorkoutLiveActivityController.endOrphans()
                Task.detached { _ = try? await HealthSync.shared.syncIfEnabled() }
                Task.detached { await SpotlightIndex.refresh() }
            }
        }
    }
}
