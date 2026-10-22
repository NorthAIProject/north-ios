import NorthAPI
import NorthKit
import SwiftUI

/// A finished workout as somebody else reads it: the stats row, the top two
/// exercises and a chip for each personal record. One view for the feed and
/// the profile; it does not navigate, whoever holds it decides what a tap does.
struct WorkoutCardView: View {
    let card: WorkoutCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let stats = WorkoutCardFormat.stats(card)
            if !stats.isEmpty {
                Text(stats.joined(separator: " · "))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(Array(WorkoutCardFormat.top(card).enumerated()), id: \.offset) { _, exercise in
                HStack(alignment: .firstTextBaseline) {
                    Text(exercise.name).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 8)
                    if let best = exercise.best, !best.isEmpty {
                        Text(WorkoutCardFormat.best(best))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            let records = WorkoutCardFormat.recordNames(card)
            if !records.isEmpty {
                RecordChips(names: records)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// "PR · Bench press", one per record.
struct RecordChips: View {
    let names: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    PRBadge(text: "PR · \(name)")
                }
            }
        }
    }
}

struct PRBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(NorthColor.signal.opacity(0.15), in: .capsule)
            .foregroundStyle(NorthColor.signal)
            .lineLimit(1)
    }
}

extension WorkoutCard {
    /// The line above a card: its name and the day it ended.
    var titleLine: String {
        "\(name) · \(endedAt.formatted(.dateTime.day().month(.abbreviated)))"
    }
}
