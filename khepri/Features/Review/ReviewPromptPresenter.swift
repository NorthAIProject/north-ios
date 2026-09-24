import StoreKit
import SwiftUI

/// Asks iOS for the rating sheet about a second after a success makes a prompt
/// due, and only while this screen is on screen and the app is active.
/// Attach to the coach conversation: `.reviewPrompt()`.
struct ReviewPromptPresenter: ViewModifier {
    let prompter: ReviewPrompter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                // A prompt that came due while this screen was away has passed.
                if prompter.isPromptDue { prompter.skipPrompt() }
            }
            .onDisappear { isVisible = false }
            .onChange(of: prompter.isPromptDue) { _, isDue in
                guard isDue else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard isVisible, scenePhase == .active, prompter.shouldPrompt else {
                        prompter.skipPrompt()
                        return
                    }
                    prompter.didPrompt()
                    requestReview()
                }
            }
    }
}

extension View {
    func reviewPrompt(_ prompter: ReviewPrompter = .shared) -> some View {
        modifier(ReviewPromptPresenter(prompter: prompter))
    }
}
