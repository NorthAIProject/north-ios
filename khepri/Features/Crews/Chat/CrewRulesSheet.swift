import NorthKit
import SwiftUI

/// The crew rules, agreed once before the first post (App Store guideline 1.2).
/// There is only "I agree": a skippable primer was rejected before. Swiping
/// the sheet away keeps the unsent message, and the next send asks again.
struct CrewRulesSheet: View {
    let onAgree: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.largeTitle)
                .foregroundStyle(NorthColor.signal)
                .accessibilityHidden(true)
            Text("Crew rules")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            // swiftlint:disable:next line_length
            Text("No hate, harassment, sexual content involving anyone without consent, threats or spam. Content that breaks these rules is removed and accounts that post it are suspended. Report anything that crosses the line.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onAgree) {
                Text("I agree").frame(maxWidth: .infinity)
            }
            .northProminentButton()
            .controlSize(.large)
            .accessibilityIdentifier("crew-rules-agree")
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }
}
