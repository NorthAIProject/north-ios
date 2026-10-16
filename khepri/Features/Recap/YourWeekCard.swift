import NorthAPI
import NorthKit
import SwiftUI

/// "Your week" on Today: the last seven days as small bars and three
/// numbers. Tapping opens the recap.
struct YourWeekCard: View {
    let recap: Recap
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                RecapBars(days: recap.days, height: 26, showsLabels: false)
                    .frame(width: 64)
                Text("Your week").northEyebrow()
                    .lineLimit(1)
                    .layoutPriority(-1)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    Number(systemImage: "calendar", value: recap.totals.activeDays)
                    Number(systemImage: "dumbbell", value: recap.totals.workouts)
                    Number(systemImage: "face.smiling", value: recap.totals.checkIns)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .northSurfaceCard(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Your week: \(recap.totals.activeDays) active days, \(recap.totals.workouts) workouts, \(recap.totals.checkIns) check-ins"))
        .accessibilityHint(String(localized: "Opens your recap"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct Number: View {
    let systemImage: String
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.north(.subheadline).weight(.medium))
                .monospacedDigit()
                .fixedSize()
        }
    }
}
