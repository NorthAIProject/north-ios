import NorthAPI
import SwiftUI

/// A day's macros: what it adds up to, its target and what's left, and any
/// macro it goes over.
struct MealImportDayTotals: View {
    let day: MealImportDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total \(line(day.totals))")
            if let target = day.target {
                Text("Target \(line(target)) · left \(line(day.remaining))")
            }
            ForEach(day.over ?? [], id: \.self) { Text($0).foregroundStyle(.red) }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func line(_ macros: ImportMacros?) -> String {
        macros?.summary ?? "—"
    }
}
