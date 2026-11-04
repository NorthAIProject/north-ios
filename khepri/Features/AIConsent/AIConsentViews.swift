import NorthKit
import SwiftUI

/// What is sent and who receives it, as App Review guidelines 5.1.1(i) and
/// 5.1.2(i) require. Shared by the first-run question and Settings.
struct AIConsentDisclosure: View {
    let recipients: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Khepri's coach, reports, meal and training plans are written by AI models run by other companies. To answer you, Khepri sends them your data.")

            VStack(alignment: .leading, spacing: 12) {
                Text("What is sent").font(.headline)
                row("text.bubble", "What you write: coach messages, check-ins, journal entries, goals and decisions")
                row("heart", "Health and fitness: workouts, sleep, weight, measurements, nutrition, medications and data you share from Apple Health")
                row("person", "About you: your name, age, time zone, coaching style, and what the coach remembers about you")
                row("doc", "Only when you choose to send or connect them: files, photos and your calendar")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Who receives it").font(.headline)
                ForEach(recipients, id: \.self) { recipient in
                    Label {
                        Text(verbatim: recipient)
                    } icon: {
                        Image(systemName: "building.2").foregroundStyle(NorthColor.signal)
                    }
                }
                Text("If you connect your own AI provider in Settings, it receives this data first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Your data is used to answer you and to run these features. Khepri does not sell it or use it for advertising.")

            Link("Read the privacy policy", destination: AppEnvironment.privacyURL)
        }
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(NorthColor.signal)
        }
    }
}

/// Asked once per account before anything is sent. Declining keeps the rest
/// of the app working.
struct AIConsentScreen: View {
    @Environment(AIConsentCenter.self) private var consent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Share your data with AI?")
                    .font(.title.weight(.semibold))
                AIConsentDisclosure(recipients: consent.recipients)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let error = consent.saveError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button("Allow") { Task { await consent.decide(allow: true) } }
                    .northProminentButton()
                    .controlSize(.large)
                    .accessibilityIdentifier("ai-consent-allow")
                Button("Don't Allow") { Task { await consent.decide(allow: false) } }
                    .controlSize(.large)
                    .accessibilityIdentifier("ai-consent-decline")
                Text("If you don't allow this, AI features stay off and nothing is sent. You can change this in Settings under AI Data Sharing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .disabled(consent.isSaving)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .interactiveDismissDisabled()
    }
}

/// Settings > AI Data Sharing: the same disclosure and a way to change the answer.
struct AIConsentSettings: View {
    @Environment(AIConsentCenter.self) private var consent

    var body: some View {
        List {
            Section {
                AIConsentDisclosure(recipients: consent.recipients)
                    .padding(.vertical, 8)
            }
            Section {
                Toggle("Allow AI data sharing", isOn: Binding(
                    get: { consent.choice == .allowed },
                    set: { allow in Task { await consent.decide(allow: allow) } }
                ))
                .disabled(consent.isSaving || consent.choice == .unknown)
                .accessibilityIdentifier("ai-consent-toggle")
            } footer: {
                if let error = consent.saveError {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("When this is off, AI features stay off and nothing is sent. Data already sent is not recalled.")
                }
            }
        }
        .navigationTitle("AI Data Sharing")
        .task { await consent.load() }
    }
}

/// Stands in for the Coach tab when AI data sharing is off.
struct AIOffView: View {
    @Environment(AIConsentCenter.self) private var consent

    var body: some View {
        ContentUnavailableView {
            Label("AI is off", systemImage: "sparkles")
        } description: {
            Text("The coach needs to send your data to AI providers to answer you. You turned that off.")
        } actions: {
            NavigationLink("Review AI Data Sharing") { AIConsentSettings() }
                .accessibilityIdentifier("ai-off-review")
        }
    }
}
