import NorthAPI
import SwiftUI

/// The saved first-versus-latest observation and the button that makes or
/// refreshes it. A model's observation from photos, labelled as one every
/// time; nothing runs until the person asks.
struct ProgressComparisonSection: View {
    let store: ProgressCheckStore

    var body: some View {
        let list = store.list
        Section {
            if let comparison = list?.comparison {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Observation from photos, not a measurement · \(ProgressCheckText.confidence(comparison.confidence))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(comparison.summary)
                    if let limits = comparison.limits, !limits.isEmpty {
                        Text("Limits: \(limits)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Read by \(comparison.providerLabel).").font(.caption).foregroundStyle(.secondary)
                    if comparison.stale {
                        Text("You have a newer check since. Compare again to include it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("progress-compare-stale")
                    }
                }
                .accessibilityIdentifier("progress-comparison")
            }
            if let error = store.compareError {
                ErrorRow(error)
            }
            if list?.canCompare == true, let assist = store.assist, assist.available,
               let provider = assist.providerLabel {
                Button {
                    Task { await store.compare() }
                } label: {
                    if store.comparing {
                        Label("Comparing…", systemImage: "hourglass")
                    } else if list?.comparison != nil {
                        Label("Compare again", systemImage: "arrow.left.arrow.right")
                    } else {
                        Label("Compare first and latest", systemImage: "arrow.left.arrow.right")
                    }
                }
                .disabled(store.comparing)
                .accessibilityIdentifier("progress-compare")
                Text(assist.ownProvider
                    ? "Sends the front and side photos of your first and latest checks to \(provider), on your own key. The result is saved here and your coach can read it."
                    : "Sends the front and side photos of your first and latest checks to \(provider). The result is saved here and your coach can read it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("First and latest, compared")
        } footer: {
            if let comparison = list?.comparison {
                Text("\(ProgressCheckText.date(comparison.fromOn)) → \(ProgressCheckText.date(comparison.toOn))")
            } else {
                Text("You have two checks with photos. Compare them to see what changed.")
            }
        }
    }
}
