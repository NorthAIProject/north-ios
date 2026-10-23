import GoogleSignIn
import NorthAPI
import NorthKit
import SwiftUI

@main
struct KhepriApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var app = AppModel()
    @State private var router = AppRouter()
    @State private var tour = GuidedTour()
    @State private var crewUnread = CrewUnread()
    @State private var awards = AwardsCenter()

    init() {
        NorthFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(router)
                .environment(tour)
                .environment(crewUnread)
                .environment(awards)
                .task {
                    delegate.onOpenURL = { router.open(url: $0) }
                    delegate.onCrewPush = {
                        guard case .signedIn = app.phase else { return }
                        Task { await crewUnread.refresh() }
                    }
                    await app.start()
                }
                // Badges belong to whoever is signed in.
                .onChange(of: app.phase) { _, phase in
                    if case .signedIn = phase { return }
                    crewUnread.reset()
                    awards.reset()
                }
                .onReceive(NotificationCenter.default.publisher(for: .authSessionDidInvalidate)) { _ in
                    app.sessionEnded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .dayDataDidChange)) { _ in
                    router.dataChanged()
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
            case .waitingForUnlock:
                UnlockWaitingView()
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
        // On the windows rather than `.preferredColorScheme`: it reaches
        // UIKit-presented sheets too, and going back to System undoes cleanly.
        .onAppear { app.appearance.apply() }
        .onChange(of: app.appearance) { _, appearance in appearance.apply() }
    }
}
