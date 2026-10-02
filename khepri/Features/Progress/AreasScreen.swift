import Charts
import NorthAPI
import NorthKit
import SwiftUI

typealias InsightsAreas = Components.Schemas.InsightsAreas
typealias InsightsArea = Components.Schemas.InsightsArea

protocol AreasServicing: Sendable {
    func areas(weeks: Int) async throws -> InsightsAreas
}

struct AreasService: AreasServicing {
    var api: Client = API.shared

    func areas(weeks: Int) async throws -> InsightsAreas {
        try await NorthAPI.call { try await api.getInsightsAreas(query: .init(weeks: weeks)).ok.body.json }
    }
}

/// Pushes the scoreboard from the Areas section.
struct AreasRoute: Hashable {}

/// The life-area scoreboard: each area's score this week, with its last
/// weeks beside it, and this week's focus from the weekly review on top.
struct AreasScreen: View {
    var service: AreasServicing = AreasService()
    @State private var areas: InsightsAreas?
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let areas {
                if !areas.focus.isEmpty {
                    Section("This Week's Focus") {
                        ForEach(areas.focus, id: \.self) { Text($0) }
                    }
                }
                Section {
                    ForEach(areas.areas, id: \.key) { AreaRow(area: $0) }
                } footer: {
                    Text("Each line is one week, Monday to Sunday; the last is this week so far.")
                }
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Areas by Week")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            areas = try await service.areas(weeks: 8)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AreaRow: View {
    let area: InsightsArea

    /// The weeks with something logged, so a gap reads as a gap, not a zero.
    private var points: [(week: Int, points: Int)] {
        area.trend.enumerated().compactMap { index, point in point.hasData ? (index, point.points) : nil }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(area.label).font(.headline)
                    if area.hasData, !area.verdict.isEmpty {
                        Text(area.verdict).northEyebrow()
                    }
                }
                Text(area.hasData ? "\(area.points) this week" : "Not enough logged this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Chart(points, id: \.week) { point in
                LineMark(x: .value("Week", point.week), y: .value("Score", point.points))
                    .foregroundStyle(NorthColor.signal)
                PointMark(x: .value("Week", point.week), y: .value("Score", point.points))
                    .foregroundStyle(NorthColor.signal)
                    .symbolSize(12)
            }
            .chartXScale(domain: 0...max(area.trend.count - 1, 1))
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 110, height: 36)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let trend = points.map { "\($0.points)" }.joined(separator: ", ")
        let now = area.hasData ? "\(area.points) this week, \(area.verdict)" : "not enough logged this week"
        return "\(area.label), \(now). Weekly scores: \(trend.isEmpty ? "none yet" : trend)"
    }
}
