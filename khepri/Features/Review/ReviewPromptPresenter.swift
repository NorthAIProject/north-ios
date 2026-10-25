import StoreKit
import SwiftUI

/// Asks iOS for the rating sheet about a second and a half after a success or
/// a milestone makes a prompt due, once the screen's animations have settled,
/// and only while this screen is on screen and the app is active. A prompt that
/// came due on a screen without a presenter is asked when the next one appears.
/// Attach to a screen where things go well: `.reviewPrompt()`.
///
/// Does nothing under the UI tests: debug builds always show the sheet, and it
/// would cover the screens the tests are driving.
struct ReviewPromptPresenter: ViewModifier {
    let prompter: ReviewPrompter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                if prompter.isPromptDue { askAfterSettling() }
            }
            .onDisappear { isVisible = false }
            .onChange(of: prompter.isPromptDue) { _, isDue in
                if isDue { askAfterSettling() }
            }
    }

    private func askAfterSettling() {
        guard !UITesting.isLaunchedByTests else {
            prompter.skipPrompt()
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            // Already asked, or let go, by another check that got here first.
            guard prompter.isPromptDue else { return }
            guard isVisible, scenePhase == .active, prompter.shouldPrompt else {
                prompter.skipPrompt()
                return
            }
            prompter.didPrompt()
            requestReview()
        }
    }
}

extension View {
    func reviewPrompt(_ prompter: ReviewPrompter = .shared) -> some View {
        modifier(ReviewPromptPresenter(prompter: prompter))
    }
}
