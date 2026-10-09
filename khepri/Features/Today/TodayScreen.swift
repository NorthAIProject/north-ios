import NorthAPI
import NorthKit
import SwiftUI

/// Loads Today and keeps it fresh: on appear, on pull-to-refresh, when the
/// app returns to the foreground or the tab is picked again, since the web or
/// Telegram may have changed it meanwhile, and after any write on this device.
struct TodayScreen: View {
    @State private var state: LoadState = .loading
    @State private var dayStore: DayStore
    @State private var addingToDay = false
    /// The router's data version the last load started at, so a change this
    /// screen has already caught up with does not load twice.
    @State private var loadedVersion: Int?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router

    private let auth: AuthServicing

    init(auth: AuthServicing = AuthService.shared, day: DayServicing = DayService()) {
        self.auth = auth
        _dayStore = State(initialValue: DayStore(service: day))
    }

    enum LoadState {
        case loading
        case loaded(TodaySnapshot)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let snapshot):
                    TodayView(snapshot: snapshot, dayStore: dayStore)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Today did not load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                }
            }
            .navigationTitle(dayStore.isToday ? "Today" : dayTitle)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { Task { await dayStore.step(-1) } } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous day")
                    if !dayStore.isToday {
                        Button("Today") { Task { await dayStore.goToToday() } }
                    }
                    Button { Task { await dayStore.step(1) } } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next day")
                }
                ToolbarItem(placement: .primaryAction) { NudgesBellButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { addingToDay = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Add to your day")
                }
            }
            .sheet(isPresented: $addingToDay) { QuickAddSheet(store: dayStore) }
            .navigationDestination(for: FitnessRoute.self) { _ in FitnessScreen() }
            .refreshable { await load() }
        }
        .task(id: router.dataVersion) {
            guard loadedVersion != router.dataVersion else { return }
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        // The tab bar keeps Today alive, so coming back to it loads nothing
        // by itself.
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .today { Task { await load() } }
        }
        // A quick add already reloaded My Day; the tiles above it and every
        // other screen showing the day follow.
        .onChange(of: dayStore.writes) {
            router.dataChanged()
            loadedVersion = router.dataVersion
            Task { await loadSnapshot() }
        }
    }

    private var dayTitle: String {
        (dayStore.date ?? .now).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func load() async {
        loadedVersion = router.dataVersion
        // My Day loads beside Today; neither waits for the other.
        async let day: Void = dayStore.load()
        await loadSnapshot()
        await day
    }

    private func loadSnapshot() async {
        do {
            state = .loaded(try await auth.today().snapshot)
        } catch {
            // A newer change cancelled this load and started the next one.
            if Task.isCancelled { return }
            // Keep what is on screen if a refresh fails; only an empty screen
            // shows the error.
            if case .loaded = state {} else { state = .failed(error.localizedDescription) }
        }
    }
}
