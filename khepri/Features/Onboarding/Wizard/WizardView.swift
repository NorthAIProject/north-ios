import NorthAPI
import NorthKit
import SwiftUI

/// The first-run wizard: six short steps from welcome to permissions.
struct WizardView: View {
    @State private var model: WizardModel
    let onComplete: (APIUser) -> Void
    let onSignOut: () -> Void

    init(user: APIUser, onComplete: @escaping (APIUser) -> Void, onSignOut: @escaping () -> Void) {
        _model = State(initialValue: WizardModel(user: user))
        self.onComplete = onComplete
        self.onSignOut = onSignOut
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // A new identity per step, so SwiftUI animates step to step and
            // the first step renders at full opacity (Lumina's fix for a
            // blank first screen under `.transition`).
            stepView
                .id(model.step)
                .transition(.push(from: .trailing))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy, value: model.step)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .opacity(model.canGoBack ? 1 : 0)
            .disabled(!model.canGoBack)
            .accessibilityLabel("Back")

            ProgressView(value: model.step.progress)
                .tint(NorthColor.signal)
                .animation(.snappy, value: model.step)

            Menu {
                Button("Sign Out", role: .destructive, action: onSignOut)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model, next: next)
        case .focusAreas: FocusAreasStep(model: model, next: next)
        case .coachingStyle: CoachingStyleStep(model: model, next: next)
        case .firstGoal: FirstGoalStep(model: model, next: next)
        case .health: HealthStep(next: next)
        case .notifications: NotificationsStep(next: next)
        }
    }

    private func next() {
        Task {
            if let user = await model.advance() {
                onComplete(user)
            }
        }
    }
}

/// The shared layout of every step: a headline, optional supporting line,
/// the step's content, and the call to action pinned to the bottom.
struct WizardChrome<Content: View>: View {
    let headline: String
    var subhead: String?
    let primary: String
    var primaryEnabled = true
    var isWorking = false
    var secondary: String?
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(headline)
                    .font(.title.weight(.semibold))
                if let subhead {
                    Text(subhead)
                        .foregroundStyle(.secondary)
                }
                content
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        // Pinned with safeAreaInset rather than stacked under the scroll view:
        // a sibling competes for height and can collapse the content.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onPrimary) {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(primary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!primaryEnabled || isWorking)

                if let secondary, let onSecondary {
                    Button(secondary, action: onSecondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}
