import NorthAPI
import NorthKit
import SwiftUI

/// Loads Today and keeps it fresh: on appear, on pull-to-refresh, and when the
/// app returns to the foreground, since the web or Telegram may have changed
/// it meanwhile.
struct TodayScreen: View {
    @State private var state: LoadState = .loading
    @State private var dayStore: DayStore
    @Environment(\.scenePhase) private var scenePhase

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
            }
            .refreshable { await load() }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private var dayTitle: String {
        (dayStore.date ?? .now).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func load() async {
        // My Day loads beside Today; neither waits for the other.
        async let day: Void = dayStore.load()
        do {
            state = .loaded(try await auth.today().snapshot)
        } catch {
            // Keep what is on screen if a refresh fails; only an empty screen
            // shows the error.
            if case .loaded = state {} else { state = .failed(error.localizedDescription) }
        }
        await day
    }
}
