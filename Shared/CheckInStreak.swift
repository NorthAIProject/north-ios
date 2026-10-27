import Foundation
import NorthAPI

/// How one day of the week reads. The server sends an open string; a state
/// this build does not know reads as `none`, never as a failure.
enum CheckInDayState: Equatable, Sendable {
    case checked, rest, none, today, upcoming

    init(_ raw: String) {
        switch raw {
        case "checked": self = .checked
        case "rest": self = .rest
        case "today": self = .today
        case "upcoming": self = .upcoming
        default: self = .none
        }
    }
}

/// A check-in run as the app and the widgets show it: the days, the best run,
/// the rest days, and this week Monday to Sunday.
struct CheckInStreak: Equatable, Sendable {
    var days: Int
    var best = 0
    var restsHeld = 0
    var restsUsed = 0
    var perfectWeek = false
    var week: [CheckInDayState] = []

    init(days: Int, best: Int = 0, restsHeld: Int = 0, restsUsed: Int = 0,
         perfectWeek: Bool = false, week: [CheckInDayState] = []) {
        self.days = days
        self.best = best
        self.restsHeld = restsHeld
        self.restsUsed = restsUsed
        self.perfectWeek = perfectWeek
        self.week = week
    }

    init(_ list: Components.Schemas.CheckInList) {
        self.init(
            days: list.streak, best: list.bestStreak, restsHeld: list.restDaysHeld, restsUsed: list.restDaysUsed,
            perfectWeek: list.perfectWeek, week: list.week.map { CheckInDayState($0.state) }
        )
    }

    /// The line over today's check-in. A rest day is said plainly; after a
    /// break it names the best run rather than the gap. Empty before the
    /// first check-in.
    var headline: String {
        if days == 0 {
            return best > 0 ? String(localized: "New run starts today · best \(best)") : ""
        }
        if days == 1 && best >= 3 {
            return String(localized: "Day one of a new run · best \(best)")
        }
        let run = days == 1 ? String(localized: "1 day in a row") : String(localized: "\(days) days in a row")
        switch restsUsed {
        case 0: return run
        case 1: return run + " · " + String(localized: "1 rest day")
        default: return run + " · " + String(localized: "\(restsUsed) rest days")
        }
    }

    /// Rest days in hand, or nil with none.
    var restsLabel: String? {
        switch restsHeld {
        case 0: nil
        case 1: String(localized: "1 rest day in hand")
        default: String(localized: "\(restsHeld) rest days in hand")
        }
    }
}
