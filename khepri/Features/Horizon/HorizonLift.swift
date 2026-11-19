import Foundation
import NorthAPI

/// A suggested first working set for a lift, as the server worked it out
/// from the last session. A starting point for the set sheet, never a rule.
nonisolated struct NextSet: Equatable, Sendable, Codable {
    let weightKg: Double
    let reps: Int
    /// Why, already worded: "One more rep than last time".
    let reason: String
}

/// One lift behind its forecast: what was logged, the range ahead, how the
/// method has done on this lift before, and the last form check of it.
nonisolated struct HorizonLiftDetail: Equatable, Sendable {
    struct Logged: Equatable, Sendable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// A four-week forecast the method would have made, and what happened.
    struct Past: Equatable, Sendable, Identifiable {
        let madeOn: Date
        let predicted: Double
        let actual: Double
        var id: Date { madeOn }
    }

    struct FormNote: Equatable, Sendable {
        let analysisID: String
        let date: Date
        let summary: String
        /// "high", "medium" or "low"; anything else reads as low.
        let confidence: String
        let cue: String?
    }

    let series: HorizonSeries
    /// Oldest first.
    let history: [Logged]
    let past: [Past]
    let formNote: FormNote?

    /// The forecast's days as dates counted from today, for the chart.
    func ahead(from today: Date, calendar: Calendar = .current) -> [(date: Date, point: HorizonSeries.Point)] {
        guard series.isReady else { return [] }
        return series.points.compactMap { point in
            calendar.date(byAdding: .day, value: point.offsetDays, to: today).map { ($0, point) }
        }
    }

    /// History the chart draws: twice the forecast's reach and at least
    /// twelve weeks, so a long past never squeezes the range into a corner.
    func recent(from today: Date, calendar: Calendar = .current) -> [Logged] {
        let days = max(series.reach * 2, 84)
        guard let since = calendar.date(byAdding: .day, value: -days, to: today) else { return history }
        return history.filter { $0.date >= since }
    }
}

nonisolated extension HorizonLiftDetail {
    private static let dayFormat: Date.ISO8601FormatStyle = .iso8601.year().month().day()

    /// A server calendar date; noon keeps it on its day in any zone.
    private static func day(_ text: String) -> Date? {
        (try? dayFormat.parse(text))?.addingTimeInterval(12 * 3600)
    }

    init(_ response: Components.Schemas.HorizonLiftDetail, measure: String) {
        let lift = response.value1
        var series = HorizonSeries(lift.value1, id: "lift:" + lift.value2.key, name: lift.value2.name, note: lift.value2.plateauText)
        series.measure = measure
        self.series = series
        history = response.value2.history
            .compactMap { point in Self.day(point.date).map { Logged(date: $0, value: point.value) } }
            .sorted { $0.date < $1.date }
        past = response.value2.past
            .compactMap { miss in Self.day(miss.madeOn).map { Past(madeOn: $0, predicted: miss.predicted, actual: miss.actual) } }
            .sorted { $0.madeOn > $1.madeOn }
        formNote = response.value2.formNote.flatMap { note in
            Self.day(note.date).map {
                FormNote(analysisID: note.analysisId, date: $0, summary: note.summary, confidence: note.confidence,
                         cue: note.cue.flatMap { $0.isEmpty ? nil : $0 })
            }
        }
    }
}
