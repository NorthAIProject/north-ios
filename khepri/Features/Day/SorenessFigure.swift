import Foundation
import NorthAPI

/// Reported soreness on the body figure: which muscles a day's sore regions
/// colour, which region a tapped muscle logs, and the strip of recent days.
///
/// The region → muscle map comes from the server (`GET /soreness`, `figure`),
/// so the app keeps no copy of it. Knees and feet cover no muscle and stay
/// chips.
nonisolated struct SorenessFigure: Equatable, Sendable {
    struct Day: Equatable, Sendable, Identifiable {
        /// `yyyy-MM-dd`.
        let date: String
        /// The day's worst severity; 0 when nothing was reported.
        var severity = 0
        var id: String { date }
    }

    /// Where each severity sits on the figure's ramp, 1 stiff to 3 painful.
    /// Spread wider than severity/3: the ramp starts a little way up, so an
    /// even split leaves stiff and painful both reading red. Same as the web.
    static func heat(severity: Int) -> Double {
        switch severity {
        case ...0: 0
        case 1: 0.05
        case 2: 0.5
        default: 1
        }
    }

    /// Muscle key → 0…1, for the figure's soreness ramp.
    let heat: [String: Double]
    /// Muscle key → the soreness region a tap on it logs.
    let regionOf: [String: String]
    /// Oldest first; empty when the history could not be read.
    let strip: [Day]

    init(
        entries: [Components.Schemas.DaySoreness],
        figure: [String: [String]],
        history: SorenessHistory? = nil
    ) {
        var heat: [String: Double] = [:]
        for entry in entries {
            let value = Self.heat(severity: entry.severity)
            for muscle in figure[entry.region] ?? [] {
                heat[muscle] = max(heat[muscle] ?? 0, value)
            }
        }
        self.heat = heat
        regionOf = Self.regions(byMuscle: figure)
        strip = history.map(Self.strip) ?? []
    }

    /// A muscle two regions cover (the traps: shoulders and upper back) goes
    /// to the region that lists it first.
    static func regions(byMuscle figure: [String: [String]]) -> [String: String] {
        var out: [String: String] = [:]
        let regions = figure.keys.sorted()
        for region in regions {
            if let first = figure[region]?.first, out[first] == nil { out[first] = region }
        }
        for region in regions {
            for muscle in figure[region] ?? [] where out[muscle] == nil {
                out[muscle] = region
            }
        }
        return out
    }

    /// One cell per day the history covers, days with nothing included.
    static func strip(_ history: SorenessHistory) -> [Day] {
        guard history.days > 0, let last = CalendarDay.date(from: history.to) else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        var worst: [String: Int] = [:]
        for entry in history.entries {
            worst[entry.date] = max(worst[entry.date] ?? 0, entry.severity)
        }
        return (0..<history.days).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: last).map { date in
                let day = CalendarDay.string(from: date)
                return Day(date: day, severity: worst[day] ?? 0)
            }
        }
    }

    var soreDays: Int { strip.count { $0.severity > 0 } }
}
