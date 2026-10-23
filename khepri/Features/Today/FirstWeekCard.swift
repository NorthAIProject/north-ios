import NorthAPI
import NorthKit
import SwiftUI

typealias FirstWeek = Components.Schemas.FirstWeek

/// A new person's first seven days: one goal, one small action a day.
protocol FirstWeekServicing: Sendable {
    func current() async throws -> FirstWeek
    /// Today's action, done by the person's word. The server keeps a day
    /// already done as it was, so a second tap changes nothing.
    func markDone() async throws -> FirstWeek
}

struct FirstWeekService: FirstWeekServicing {
    var api: Client = API.shared

    func current() async throws -> FirstWeek {
        try await NorthAPI.call { try await api.getFirstWeek().ok.body.json }
    }

    func markDone() async throws -> FirstWeek {
        try await NorthAPI.call { try await api.markFirstWeekDayDone().ok.body.json }
    }
}

extension FirstWeek {
    /// Days 1 to 7 of a running week. Day 0, the start date, has nothing to
    /// do yet, and a finished or skipped week shows nothing. Status is an
    /// open string, so anything unknown counts as not running.
    var isUnderWay: Bool { status == "active" && (1...totalDays).contains(day) }

    /// Days 1 to 3 all done, read on day 3: the same moment the web shows.
    var threeForThree: Bool {
        let opening = days.filter { $0.day <= 3 }
        return day == 3 && opening.count == 3 && opening.allSatisfy(\.done)
    }
}

/// The first week, loaded by the Today screen.
///
/// The screen loads it rather than the card: a card that renders nothing
/// until it has loaded never appears, so a `.task` on it never runs.
@MainActor
@Observable
final class FirstWeekStore {
    private(set) var week: FirstWeek?
    private(set) var saving = false
    private(set) var error: String?
    private let service: FirstWeekServicing

    init(service: FirstWeekServicing = FirstWeekService()) {
        self.service = service
    }

    func load() async {
        if let latest = try? await service.current() { week = latest }
    }

    func markDone() async {
        saving = true
        defer { saving = false }
        do {
            week = try await service.markDone()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Day N of 7" with today's action and a Done button, while a first week
/// runs. Shows nothing for anyone else.
struct FirstWeekCard: View {
    let store: FirstWeekStore

    var body: some View {
        if let week = store.week, week.isUnderWay {
            content(week)
        }
    }

    private func content(_ week: FirstWeek) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader(String(localized: "Day \(week.day) of \(week.totalDays)", comment: "Title of the first-week card on Today"))
            if let action = week.action, !action.isEmpty {
                Text(action).font(.subheadline)
            }
            HStack(spacing: 6) {
                ForEach(week.days, id: \.day) { day in
                    Circle()
                        .fill(day.done ? NorthColor.signal : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(week.doneCount) of \(week.totalDays) days done", comment: "First-week progress, read by VoiceOver"))
            if week.threeForThree {
                Label("3 of 3 days. You have kept it every day so far.", systemImage: "sparkles")
                    .font(.footnote)
            }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if week.done {
                Label("Done for today", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button(String(localized: "Done", comment: "Marks today's first-week action done")) {
                    Task { await store.markDone() }
                }
                .northProminentButton()
                .disabled(store.saving)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .northSurfaceCard(padding: 16)
    }
}
