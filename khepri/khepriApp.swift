//
//  khepriApp.swift
//  khepri
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import SwiftUI
import GoogleSignIn
import NorthKit

@main
struct khepriApp: App {
    @State private var isAuthenticated: Bool = false
    @State private var isCheckingAuth: Bool = true
    @State private var bootstrapUser: UserDTO?
    @State private var todaySnapshot: TodaySnapshotDTO?
    @State private var bootstrapError: String?

    init() {
        NorthFont.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isCheckingAuth {
                    ZStack {
                        Color(uiColor: .systemBackground).ignoresSafeArea()
                        ProgressView()
                    }
                } else if isAuthenticated {
                    if let bootstrapUser {
                        if bootstrapUser.needsOnboarding {
                            OnboardingView(user: bootstrapUser, onComplete: { user in
                                withAnimation {
                                    self.bootstrapUser = user
                                }
                                Task { await loadToday() }
                            }, onSignOut: signOut)
                        } else if let todaySnapshot {
                            TodayView(snapshot: todaySnapshot, onSignOut: signOut)
                        }
                    } else if let bootstrapError {
                        VStack(spacing: 12) {
                            Text("Could not load your account")
                                .font(.headline)
                            Text(bootstrapError)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try Again") {
                                Task { await loadBootstrap() }
                            }
                        }
                        .padding()
                    } else {
                        ProgressView()
                    }
                } else {
                    LoginScreen(onAuthenticated: {
                        withAnimation {
                            isAuthenticated = true
                        }
                    })
                }
            }
            .task {
                let restored = await AuthSessionManager.shared.restoreSessionIfNeeded()
                if restored {
                    isAuthenticated = true
                    await loadBootstrap()
                } else {
                    isCheckingAuth = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .authSessionDidAuthenticate)) { _ in
                Task {
                    isAuthenticated = true
                    await loadBootstrap()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .authSessionDidInvalidate)) { _ in
                withAnimation {
                    isAuthenticated = false
                    bootstrapUser = nil
                    todaySnapshot = nil
                    bootstrapError = nil
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    private func loadBootstrap() async {
        isCheckingAuth = true
        bootstrapError = nil

        do {
            let response = try await AuthService.shared.currentUser()
            withAnimation {
                bootstrapUser = response.user
                isAuthenticated = true
            }
            if !response.user.needsOnboarding {
                await loadToday()
            } else {
                isCheckingAuth = false
            }
        } catch let error as APIError where error.isUnauthorized {
            await AuthSessionManager.shared.invalidateSession()
            isCheckingAuth = false
        } catch {
            bootstrapError = error.localizedDescription
            isCheckingAuth = false
        }
    }

    private func loadToday() async {
        do {
            let response = try await AuthService.shared.today()
            withAnimation {
                todaySnapshot = response.snapshot
                bootstrapUser = response.user
                isCheckingAuth = false
            }
        } catch let error as APIError where error.isUnauthorized {
            await AuthSessionManager.shared.invalidateSession()
            isCheckingAuth = false
        } catch {
            bootstrapError = error.localizedDescription
            isCheckingAuth = false
        }
    }

    private func signOut() {
        Task {
            await AuthService.shared.logout()
        }
    }
}
