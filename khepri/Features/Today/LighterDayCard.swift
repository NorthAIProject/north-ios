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
    /// The server words it in the Progress screen's terms; a server from
    /// before recovery sends only the numbers, worded here.
    var why: String? {
        if let reason = readiness.reason, !reason.isEmpty { return reason }
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

/// Today's lighter-day state, loaded by the Today screen.
///
/// The screen loads it rather than the card: a card that renders nothing
/// until it has loaded never appears, so a `.task` on it never runs.
@MainActor
@Observable
final class LighterDayStore {
    private(set) var day: LighterDay?
    private(set) var saving = false
    private(set) var error: String?
    private let service: LighterDayServicing

    init(service: LighterDayServicing = LighterDayService()) {
        self.service = service
    }

    func load() async {
        if let latest = try? await service.today() { day = latest }
    }

    func choose(lighter: Bool) async {
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

/// On a low-recovery morning with a session still to do: take it lighter
/// (about 60% of today's sets, today only) or keep the plan. Shows nothing
/// on any other morning.
struct LighterDayCard: View {
    let store: LighterDayStore

    var body: some View {
        if let day = store.day, day.offered {
            offer(day)
        } else if let day = store.day, day.tookItLighter {
            Label("Lighter day: today's sets are cut to about 60%. Tomorrow is back to the plan.", systemImage: "leaf")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .northSurfaceCard(padding: 16)
        }
    }

    private func offer(_ day: LighterDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader("Lighter Day?")
            Text("Your body hasn't caught up this morning. Train about 60% of today's sets\(day.session.map { " for \($0)" } ?? ""), or keep the plan.")
                .font(.subheadline)
            if let why = day.why {
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Take It Lighter") { Task { await store.choose(lighter: true) } }
                    .northProminentButton()
                Button("Keep the Plan") { Task { await store.choose(lighter: false) } }
                    .buttonStyle(.bordered)
            }
            .disabled(store.saving)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .northSurfaceCard(padding: 16)
    }
}
