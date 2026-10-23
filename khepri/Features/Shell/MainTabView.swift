import NorthAPI
import SwiftUI

/// The signed-in app: five tabs, each with its own navigation stack.
struct MainTabView: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @Environment(GuidedTour.self) private var tour
    @Environment(CrewUnread.self) private var crewUnread
    @Environment(AwardsCenter.self) private var awards
    @Environment(\.scenePhase) private var scenePhase
    /// A workout the app was killed during, picked up where it was.
    @State private var resumedWorkout: WorkoutSession?
    /// Whether the awards cover is asked for, and whether it is really on screen.
    @State private var celebrating = false
    @State private var celebrationVisible = false

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
            // Unread crew messages; 0 hides the badge.
            .badge(crewUnread.total)
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
        // Closing the check-in refreshes the tab under it, however the sheet
        // went away: Done or a swipe.
        .onChange(of: router.showsCheckInFlow) { _, shown in
            if !shown { router.dataChanged() }
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
        // A muscle tapped on the body figure: its exercises, from any tab.
        .sheet(item: Binding(
            get: { router.openMuscle.map(MuscleLibraryRoute.init(muscle:)) },
            set: { router.openMuscle = $0?.muscle }
        )) { route in
            NavigationStack {
                ExerciseLibrary(service: TrainingService(), muscle: route.muscle)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { router.openMuscle = nil } }
                    }
            }
        }
        .fullScreenCover(item: $resumedWorkout) { session in WorkoutSessionView(session: session) }
        // Badges just earned, one cover paging through them. Closing it, either
        // way, tells the server they were seen.
        .fullScreenCover(isPresented: $celebrating) {
            UnlockCelebrationView(
                awards: awards.pending,
                onShown: { awards.didShow($0) },
                onViewProfile: {
                    Task { await awards.dismiss() }
                    celebrating = false
                    router.opensOwnAwards = true
                    router.open(.tab(.progress))
                },
                onDone: {
                    Task { await awards.dismiss() }
                    celebrating = false
                }
            )
            .onAppear { celebrationVisible = true }
            .onDisappear { celebrationVisible = false }
        }
        // A workout or check-in finished on this device may have earned one.
        // The cover waits a moment after the answer, since the workout's own
        // cover is still leaving when the badge arrives.
        .onChange(of: router.dataVersion) {
            Task {
                await awards.refresh()
                try? await Task.sleep(for: .milliseconds(700))
                await showCelebrationIfDue()
            }
        }
        .onChange(of: awards.pending.map(\.id)) { old, new in
            // Only a badge arriving asks for the cover; one leaving does not.
            if new.contains(where: { !old.contains($0) }) { Task { await showCelebrationIfDue() } }
        }
        // A presentation SwiftUI dropped under a sheet or the tour is asked
        // for again as soon as that goes away.
        .onChange(of: router.showsCheckInFlow) { _, shown in if !shown { Task { await showCelebrationIfDue() } } }
        .onChange(of: router.showsWeeklyReview) { _, shown in if !shown { Task { await showCelebrationIfDue() } } }
        .onChange(of: router.openExercise) { _, open in if open == nil { Task { await showCelebrationIfDue() } } }
        .onChange(of: router.openMuscle) { _, open in if open == nil { Task { await showCelebrationIfDue() } } }
        .onChange(of: resumedWorkout == nil) { _, none in if none { Task { await showCelebrationIfDue() } } }
        .onAppear { tour.startIfNeeded() }
        .task { resumedWorkout = WorkoutSession.resumingKilledWorkout() }
        // Apple Health catches up whenever the app comes forward, and
        // Spotlight's copy of exercises and goals with it; each decides for
        // itself whether there is anything to do. A workout Live Activity with
        // no workout behind it (one stopped on the web, say) ends here too;
        // one a killed workout left is kept for the resumed workout. Crew
        // badges catch up with pushes that arrived while it was away.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                WorkoutLiveActivityController.endOrphans()
                Task { await crewUnread.refresh() }
                Task {
                    await awards.refresh()
                    await showCelebrationIfDue()
                }
                Task.detached { _ = try? await HealthSync.shared.syncIfEnabled() }
                Task.detached { await SpotlightIndex.refresh() }
            }
        }
    }

    /// Presents the cover when badges are waiting and it is not on screen. If
    /// it was asked for but never appeared (SwiftUI drops a cover requested
    /// while another presentation is up), it is asked for again.
    private func showCelebrationIfDue() async {
        guard !awards.pending.isEmpty, !celebrationVisible else { return }
        if celebrating {
            celebrating = false
            try? await Task.sleep(for: .milliseconds(350))
            guard !awards.pending.isEmpty, !celebrationVisible else { return }
        }
        celebrating = true
    }
}

private struct MuscleLibraryRoute: Identifiable {
    let muscle: String
    var id: String { muscle }
}
