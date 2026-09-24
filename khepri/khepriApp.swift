import GoogleSignIn
import NorthAPI
import NorthKit
import SwiftUI

@main
struct KhepriApp: App {
    @State private var app = AppModel()
    @State private var router = AppRouter()
    @State private var tour = GuidedTour()

    init() {
        NorthFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(router)
                .environment(tour)
                .task { await app.start() }
                .onReceive(NotificationCenter.default.publisher(for: .authSessionDidInvalidate)) { _ in
                    app.sessionEnded()
                }
                .onOpenURL { url in
                    // Google's sign-in callback, else one of our own links.
                    if !GIDSignIn.sharedInstance.handle(url) {
                        router.open(url: url)
                    }
                }
        }
    }
}

/// Picks the root screen from the app's phase.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                LoginScreen(onAuthenticated: {
                    Task { await app.didSignIn() }
                })
            case .onboarding(let user):
                WizardView(
                    user: user,
                    onComplete: { app.didCompleteOnboarding($0) },
                    onSignOut: { Task { await app.signOut() } }
                )
            case .signedIn(let user):
                MainTabView(user: user)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load your account", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await app.retry() } }
                    Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
    }
}
