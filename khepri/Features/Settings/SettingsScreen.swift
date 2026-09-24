import NorthAPI
import SwiftUI

/// Settings, presented as a sheet from More. Phase 2 adds the coach and
/// connection settings; for now it holds the account and the tour.
struct SettingsScreen: View {
    let user: APIUser
    @Environment(AppModel.self) private var app
    @Environment(GuidedTour.self) private var tour
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Name", value: user.displayName.isEmpty ? "—" : user.displayName)
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Time zone", value: user.timezone)
                }

                Section {
                    Button("Show me around") {
                        Task {
                            await tour.restart()
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Replays the three-step tour of Today, Coach and Training.")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        confirmingSignOut = true
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionDescription)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of Khepri?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await app.signOut() }
                }
            }
        }
    }
}

private extension Bundle {
    /// "1.0 (42)"
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
