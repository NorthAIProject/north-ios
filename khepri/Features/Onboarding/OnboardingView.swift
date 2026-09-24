import NorthAPI
import SwiftUI

struct OnboardingView: View {
    let user: APIUser
    let onComplete: (APIUser) -> Void
    let onSignOut: () -> Void

    @State private var focusAreas: Set<String> = []
    @State private var coachingStyle = "supportive"
    @State private var customStyle = ""
    @State private var nearTermGoal = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let availableFocusAreas = ["fitness", "health", "work", "learning", "personal"]
    private let styles = [
        ("direct", "Direct"),
        ("supportive", "Supportive"),
        ("socratic", "Socratic"),
        ("custom", "Custom")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose what North should keep in view, how you want to be coached, and one goal to begin with.")
                        .foregroundStyle(.secondary)
                }

                Section("Focus areas") {
                    ForEach(availableFocusAreas, id: \.self) { area in
                        Button {
                            if focusAreas.contains(area) {
                                focusAreas.remove(area)
                            } else {
                                focusAreas.insert(area)
                            }
                        } label: {
                            HStack {
                                Text(area.capitalized)
                                Spacer()
                                if focusAreas.contains(area) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Coaching style") {
                    Picker("Style", selection: $coachingStyle) {
                        ForEach(styles, id: \.0) { style in
                            Text(style.1).tag(style.0)
                        }
                    }

                    if coachingStyle == "custom" {
                        TextField("Describe how you want to be coached", text: $customStyle, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }

                Section("One near-term goal") {
                    TextField("What are you working toward?", text: $nearTermGoal, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Text(isSubmitting ? "Saving..." : "Continue")
                            if isSubmitting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSubmitting || focusAreas.isEmpty || nearTermGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Your starting point")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive, action: onSignOut)
                }
            }
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let answers = OnboardingAnswers(
            focusAreas: availableFocusAreas.filter { focusAreas.contains($0) },
            coachingStyle: coachingStyle,
            coachingStyleCustom: customStyle,
            nearTermGoal: nearTermGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let user = try await AuthService.shared.completeOnboarding(answers)
            onComplete(user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
