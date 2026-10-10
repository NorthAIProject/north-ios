import NorthAPI
import NorthKit
import SwiftUI

/// Opens the consistency page from Progress.
struct ConsistencyRoute: Hashable {}

/// How steadily someone shows up: twelve weeks of days, a column a week,
/// with the streaks and the week against the usual one.
struct ConsistencyPage: View {
    let service: InsightsServicing

    @State private var model: InsightsConsistency?
    @State private var error: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if let error {
                ContentUnavailableView("This did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Consistency")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                model = try await service.consistency()
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func content(_ model: InsightsConsistency) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(model.thisWeek) of 7")
                        .northDisplayNumber(.largeTitle)
                    Text(Self.weekLine(model))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("This Week")
            }
            Section {
                DayGrid(days: model.days)
                    .padding(.vertical, 8)
                HStack(spacing: 16) {
                    Legend(color: NorthColor.signal, label: "Trained")
                    Legend(color: NorthColor.signal.opacity(0.45), label: "Checked in")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Twelve Weeks")
            } footer: {
                Text("A day counts with a finished workout, lifted sets or a check-in. One column a week, Monday at the top.")
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        stat("Current Streak", Self.days(model.currentStreak))
                        stat("Longest Streak", Self.days(model.longestStreak))
                    }
                    GridRow {
                        stat("Longest Gap", Self.days(model.longestGap))
                        stat("Best Week", "\(model.bestWeek.days) of 7")
                    }
                    if model.checkInStreak > 0 {
                        GridRow {
                            stat("Check-in Streak", Self.days(model.checkInStreak))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    /// "Usually 4.5 active days a week", or a first-week line.
    static func weekLine(_ model: InsightsConsistency) -> String {
        guard model.usualPerWeek > 0 else { return "Active days so far this week." }
        return String(format: "Active days so far. Usually %.1f a week.", model.usualPerWeek)
    }
}

/// Twelve columns of seven squares, oldest week on the left.
private struct DayGrid: View {
    let days: [Components.Schemas.InsightsConsistencyDay]

    var body: some View {
        let columns = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 4) {
                    ForEach(week, id: \.date) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(day))
                            .aspectRatio(1, contentMode: .fit)
                    }
                    // Keep the current, partial week's column the same height.
                    ForEach(0..<(7 - week.count), id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(days.filter { $0.trained || $0.checkedIn }.count) active days in the last twelve weeks")
    }

    private func color(_ day: Components.Schemas.InsightsConsistencyDay) -> Color {
        if day.trained { return NorthColor.signal }
        if day.checkedIn { return NorthColor.signal.opacity(0.45) }
        return Color(.tertiarySystemFill)
    }
}

private struct Legend: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }
}
