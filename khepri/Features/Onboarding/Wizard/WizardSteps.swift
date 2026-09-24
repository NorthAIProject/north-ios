import NorthAPI
import NorthKit
import SwiftUI

struct WelcomeStep: View {
    let model: WizardModel
    let next: () -> Void

    var body: some View {
        WizardChrome(
            headline: model.user.displayName.isEmpty ? "Welcome to Khepri" : "Welcome, \(model.user.displayName)",
            subhead: "A coach that remembers, across your goals, training, health and days. Four questions, then you are in.",
            primary: "Get Started",
            onPrimary: next
        ) {
            NorthBrand.mark
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityHidden(true)
        }
    }
}

struct FocusAreasStep: View {
    let model: WizardModel
    let next: () -> Void

    var body: some View {
        WizardChrome(
            headline: "What should your coach keep in view?",
            subhead: "Pick any. You can change these later.",
            primary: "Continue",
            primaryEnabled: model.canContinue,
            onPrimary: next
        ) {
            VStack(spacing: 0) {
                ForEach(Array(FocusArea.allCases.enumerated()), id: \.element) { index, area in
                    if index > 0 { Divider().padding(.leading, 52) }
                    let selected = model.draft.focusAreas.contains(area)
                    Button {
                        model.toggle(area)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: area.systemImage)
                                .frame(width: 20)
                                .foregroundStyle(NorthColor.signal)
                            Text(area.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? AnyShapeStyle(NorthColor.signal) : AnyShapeStyle(.tertiary))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            FieldError(model.fieldErrors["focus_areas"])
        }
    }
}

struct CoachingStyleStep: View {
    let model: WizardModel
    let next: () -> Void
    @FocusState private var customFocused: Bool

    private var customStyle: Binding<String> {
        Binding(get: { model.draft.customStyle }, set: { model.setCustomStyle($0) })
    }

    var body: some View {
        WizardChrome(
            headline: "How should your coach talk to you?",
            primary: "Continue",
            primaryEnabled: model.canContinue,
            onPrimary: {
                customFocused = false
                next()
            }
        ) {
            VStack(spacing: 0) {
                ForEach(Array(CoachingStyle.allCases.enumerated()), id: \.element) { index, style in
                    if index > 0 { Divider().padding(.leading, 16) }
                    let selected = model.draft.coachingStyle == style
                    Button {
                        model.choose(style)
                        customFocused = style == .custom
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.title).foregroundStyle(.primary)
                                Text(style.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(NorthColor.signal)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))

            if model.draft.coachingStyle == .custom {
                HStack(alignment: .top) {
                    TextField("For example: blunt, but ask before you push", text: customStyle, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($customFocused)
                    DictationButton(text: customStyle, font: .body)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            }
            FieldError(model.fieldErrors["coaching_style"])
        }
    }
}

struct FirstGoalStep: View {
    let model: WizardModel
    let next: () -> Void
    @FocusState private var focused: Bool

    private var goal: Binding<String> {
        Binding(get: { model.draft.goal }, set: { model.setGoal($0) })
    }

    private var suggestions: [String] {
        (model.draft.focusAreas.isEmpty ? FocusArea.allCases : model.draft.focusAreas).map(\.example)
    }

    var body: some View {
        WizardChrome(
            headline: "Name one goal to start with.",
            subhead: "Your coach opens your first conversation with it.",
            primary: "Continue",
            primaryEnabled: model.canContinue,
            isWorking: model.isSubmitting,
            onPrimary: submit
        ) {
            HStack(alignment: .top) {
                TextField("A goal you are working toward", text: goal, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit(submit)
                DictationButton(text: goal, font: .body)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))

            FieldError(model.fieldErrors["goal_title"] ?? model.submitError)

            VStack(alignment: .leading, spacing: 8) {
                Text("Ideas")
                    .northEyebrow()
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { model.setGoal(suggestion) }
                        .font(.subheadline)
                }
            }
            .padding(.top, 12)
        }
        .onAppear { focused = model.draft.goal.isEmpty }
    }

    /// Put the keyboard away first, or it follows onto the next step and
    /// covers its buttons.
    private func submit() {
        focused = false
        next()
    }
}

struct HealthStep: View {
    let next: () -> Void
    @State private var asking = false

    var body: some View {
        WizardChrome(
            headline: "Bring in Apple Health",
            subhead: "Your coach sees workouts, sleep and heart rate next to what you tell it, so advice fits the day you actually had.",
            primary: "Connect Apple Health",
            isWorking: asking,
            secondary: "Not Now",
            onPrimary: {
                Task {
                    asking = true
                    await Permissions.requestHealth()
                    // Answering the sheet is consent to sync; refused types
                    // simply return nothing.
                    HealthSync.shared.setEnabled(true)
                    HealthBackgroundDelivery.register()
                    Task.detached { _ = try? await HealthSync.shared.syncIfEnabled() }
                    asking = false
                    next()
                }
            },
            onSecondary: next
        ) {
            PrimingList(items: [
                ("figure.run", "Workouts and activity", "Steps, active energy and every workout you log."),
                ("bed.double", "Sleep and recovery", "Resting heart rate and HRV, read only."),
                ("lock", "Yours", "Choose exactly what to share on the next screen; change it any time in Settings."),
            ])
        }
    }
}

struct NotificationsStep: View {
    let next: () -> Void
    @State private var asking = false

    var body: some View {
        WizardChrome(
            headline: "A nudge before it matters",
            subhead: "Only the reminders you set up. Nothing promotional.",
            primary: "Allow Notifications",
            isWorking: asking,
            secondary: "Not Now",
            onPrimary: {
                Task {
                    asking = true
                    await Permissions.requestNotifications()
                    asking = false
                    next()
                }
            },
            onSecondary: next
        ) {
            PrimingList(items: [
                ("figure.strengthtraining.traditional", "Before a workout", "At the time you plan it, with a button to start."),
                ("drop", "Care reminders", "Water, meals and habits, at the times you choose."),
            ])
        }
    }
}

/// Why a permission is worth granting, as a short list.
private struct PrimingList: View {
    let items: [(icon: String, title: String, body: String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().padding(.leading, 52) }
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: item.icon)
                        .frame(width: 20)
                        .foregroundStyle(NorthColor.signal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
    }
}

private struct FieldError: View {
    let message: String?

    init(_ message: String?) { self.message = message }

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(NorthColor.destructive)
        }
    }
}
