import Foundation
import NorthAPI

/// What a set was for. A warm-up is logged so the workout reads as it
/// happened, but the server leaves it out of volume, records and fatigue,
/// and here it does not use up one of the plan's sets. A drop set is work.
enum SetKind: String, Codable, CaseIterable, Sendable {
    case work
    case warmup
    case drop

    /// Whether the set is training rather than preparation.
    var counts: Bool { self != .warmup }

    var title: String {
        switch self {
        case .work: String(localized: "Work")
        case .warmup: String(localized: "Warm-up")
        case .drop: String(localized: "Drop")
        }
    }

    var payload: Components.Schemas.LiftSetInput.KindPayload {
        switch self {
        case .work: .work
        case .warmup: .warmup
        case .drop: .drop
        }
    }
}

extension LiftSet {
    /// Sets logged before kinds existed, or by a server that does not send
    /// one yet, were all work sets.
    var setKind: SetKind { kind.flatMap { SetKind(rawValue: $0.rawValue) } ?? .work }
}

/// Reps in reserve as the set sheet offers them: nobody said, or 0 to 5,
/// where 5 stands for "five or more".
enum RepsInReserve {
    static let most = 5
    static let choices = Array(0...most)

    static func label(_ rir: Int) -> String { rir >= most ? "\(most)+" : "\(rir)" }
}
