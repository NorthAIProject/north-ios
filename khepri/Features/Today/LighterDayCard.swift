import NorthAPI
import NorthKit
import SwiftUI

typealias LighterDay = Components.Schemas.LighterDay

protocol LighterDayServicing: Sendable {
    func today() async throws -> LighterDay
    func choose(lighter: Bool) async throws -> LighterDay
}

struct LighterDayService: LighterDayServicing {
    var api: Client = API.shared

    func today() async throws -> LighterDay {
        try await NorthAPI.call { try await api.getLighterDay().ok.body.json }
    }

    func choose(lighter: Bool) async throws -> LighterDay {
        let choice: Operations.ChooseLighterDay.Input.Body.JsonPayload.ChoicePayload = lighter ? .lighter : .keep
        return try await NorthAPI.call { try await api.chooseLighterDay(body: .json(.init(choice: choice))).ok.body.json }
    }
}

extension LighterDay {
    /// The readings behind a low morning in a line, or nil without any.
    var why: String? {
        let r = readiness
        func change(_ value: Double, _ base: Double) -> String {
            guard base > 0 else { return "" }
            return String(format: "%+.0f%%", (value - base) / base * 100)
        }
        var parts: [String] = []
        if let hrv = r.hrv, let base = r.hrvBaseline {
            parts.append("HRV \(Int(hrv.rounded())) ms (\(change(hrv, base)))")
        }
        if let rhr = r.restingHeartRate, let base = r.restingHeartRateBaseline {
            parts.append("resting heart rate \(Int(rhr.rounded())) bpm (\(change(rhr, base)))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ").capitalizedFirst + " against your two-week average."
    }

    var tookItLighter: Bool { choice?.rawValue == "lighter" }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// On a low-readiness morning with a session still to do: take it lighter
/// (about 60% of today's sets, today only) or keep the plan. Shows nothing
/// on any other morning.
struct LighterDayCard: View {
    var service: LighterDayServicing = LighterDayService()
    @State private var day: LighterDay?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Group {
            if let day, day.offered {
                offer(day)
            } else if let day, day.tookItLighter {
                Label("Lighter day: today's sets are cut to about 60%. Tomorrow is back to the plan.", systemImage: "leaf")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .northSurfaceCard(padding: 16)
            }
        }
        .task { await load() }
    }

    private func offer(_ day: LighterDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader("Lighter Day?")
            Text("Your body hasn't caught up this morning. Train about 60% of today's sets\(day.session.map { " for \($0)" } ?? ""), or keep the plan.")
                .font(.subheadline)
            if let why = day.why {
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Take It Lighter") { Task { await choose(lighter: true) } }
                    .northProminentButton()
                Button("Keep the Plan") { Task { await choose(lighter: false) } }
                    .buttonStyle(.bordered)
            }
            .disabled(saving)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .northSurfaceCard(padding: 16)
    }

    private func load() async {
        day = try? await service.today()
    }

    private func choose(lighter: Bool) async {
        saving = true
        defer { saving = false }
        do {
            day = try await service.choose(lighter: lighter)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
