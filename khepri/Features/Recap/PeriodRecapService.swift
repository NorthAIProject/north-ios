import Foundation
import NorthAPI
import SwiftUI

typealias Recap = Components.Schemas.Recap
typealias RecapDay = Components.Schemas.RecapDay
typealias RecapTotals = Components.Schemas.RecapTotals
typealias RecapShared = Components.Schemas.RecapShared

/// The two windows a recap covers, both ending today.
enum RecapRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .week: String(localized: "7 days", comment: "Recap range picker")
        case .month: String(localized: "30 days", comment: "Recap range picker")
        }
    }

    var heading: String {
        switch self {
        case .week: String(localized: "Last 7 days")
        case .month: String(localized: "Last 30 days")
        }
    }
}

protocol PeriodRecapServicing: Sendable {
    func recap(_ range: RecapRange) async throws -> Recap
    /// Posts the recap to the friends feed. `shareTraining` also turns on
    /// training sharing, without which followers cannot see it.
    func share(_ range: RecapRange, shareTraining: Bool) async throws -> RecapShared
}

struct PeriodRecapService: PeriodRecapServicing {
    var api: Client = API.shared

    func recap(_ range: RecapRange) async throws -> Recap {
        let query: Operations.GetRecap.Input.Query.RangePayload = range == .month ? .month : .week
        return try await NorthAPI.call { try await api.getRecap(query: .init(range: query)).ok.body.json }
    }

    func share(_ range: RecapRange, shareTraining: Bool) async throws -> RecapShared {
        let body: Operations.ShareRecap.Input.Body.JsonPayload.RangePayload = range == .month ? .month : .week
        return try await NorthAPI.call {
            try await api.shareRecap(body: .json(.init(range: body, shareTraining: shareTraining))).ok.body.json
        }
    }
}

/// A YYYY-MM-DD day as a date at noon, safe from zone shifts at midnight.
private func noon(_ day: String) -> Date {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return .now }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? .now
}

extension RecapDay {
    var trained: Bool { workouts + sets > 0 }
    var ate: Bool { foodLogs > 0 }
    var checkedIn: Bool { checkIns > 0 }
    /// How many of training, food and a check-in the day had, 0–3: a day of
    /// forty sets counts the same as a day of one meal.
    var areas: Int { [trained, ate, checkedIn].count(where: \.self) }

    var calendarDate: Date { noon(date) }
}

extension Recap {
    /// "Oct 9 – 15", first and last day inclusive.
    var period: String {
        (noon(since)..<noon(until)).formatted(.interval.month(.abbreviated).day())
    }

    /// The recap in one line for a message: the window and its non-zero
    /// numbers, "label: value" so no language needs plural rules.
    func shareText(_ range: RecapRange) -> String {
        var parts = ["\(String(localized: "Active days")): \(totals.activeDays)"]
        for (label, value) in [
            (String(localized: "Workouts"), totals.workouts),
            (String(localized: "Sets"), totals.sets),
            (String(localized: "Foods logged"), totals.foodLogs),
            (String(localized: "Check-ins"), totals.checkIns),
        ] where value > 0 {
            parts.append("\(label): \(value)")
        }
        let numbers = parts.joined(separator: " · ")
        return range == .month
            ? String(localized: "My last 30 days on Khepri — \(numbers)")
            : String(localized: "My last 7 days on Khepri — \(numbers)")
    }
}

/// The recap for the Today card and the recap sheet, one per range, and the
/// state of a post to the friends feed.
@MainActor
@Observable
final class RecapStore {
    enum PostState: Equatable {
        case idle
        case posting
        case posted
        /// Posted, but training is not shared, so friends cannot see it.
        case hidden
        case failed(String)
    }

    private(set) var recaps: [RecapRange: Recap] = [:]
    private(set) var post: PostState = .idle
    private let service: PeriodRecapServicing

    init(service: PeriodRecapServicing = PeriodRecapService()) {
        self.service = service
    }

    func load(_ range: RecapRange) async {
        if let latest = try? await service.recap(range) { recaps[range] = latest }
    }

    func share(_ range: RecapRange, shareTraining: Bool = false) async {
        post = .posting
        do {
            let shared = try await service.share(range, shareTraining: shareTraining)
            post = shared.trainingShared ? .posted : .hidden
        } catch {
            post = .failed(error.localizedDescription)
        }
    }

    func resetPost() { post = .idle }
}
