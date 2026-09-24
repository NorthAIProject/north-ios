import NorthAPI
import NorthKit
import SwiftUI

/// Loads Today and keeps it fresh: on appear, on pull-to-refresh, and when the
/// app returns to the foreground, since the web or Telegram may have changed
/// it meanwhile.
struct TodayScreen: View {
    @State private var state: LoadState = .loading
    @Environment(\.scenePhase) private var scenePhase

    private let auth: AuthServicing

    init(auth: AuthServicing = AuthService.shared) {
        self.auth = auth
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
                    TodayView(snapshot: snapshot)
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
            .navigationTitle("Today")
            .refreshable { await load() }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func load() async {
        do {
            state = .loaded(try await auth.today().snapshot)
        } catch {
            // Keep what is on screen if a refresh fails; only an empty screen
            // shows the error.
            if case .loaded = state { return }
            state = .failed(error.localizedDescription)
        }
    }
}
