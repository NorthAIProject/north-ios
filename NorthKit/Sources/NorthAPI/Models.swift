import Foundation
import OpenAPIRuntime

// Short names for the generated schemas the app uses directly. The generated
// names (`Components.Schemas.User`) are exact but loud at call sites; these
// keep views readable without hiding where the types come from.

public typealias APIUser = Components.Schemas.User
public typealias AuthSession = Components.Schemas.AuthResponse
public typealias OnboardingAnswers = Components.Schemas.OnboardingRequest
public typealias TodayResponse = Components.Schemas.TodayResponse
public typealias TodaySnapshot = Components.Schemas.TodaySnapshot
public typealias TodayGoal = Components.Schemas.TodayGoal
public typealias TodayThread = Components.Schemas.TodayThread
public typealias TodayNextStep = Components.Schemas.NextStep
public typealias TodayTimelineEntry = Components.Schemas.TimelineEntry
public typealias TodayNudge = Components.Schemas.Nudge
public typealias TodayDelta = Components.Schemas.Delta

// My Day
public typealias DayResponse = Components.Schemas.DayResponse
public typealias DaySleep = Components.Schemas.DaySleep
public typealias DaySleepBlock = Components.Schemas.DaySleepBlock
public typealias DayRing = Components.Schemas.DayRing
public typealias DayTimelineEntry = Components.Schemas.DayTimelineEntry
public typealias DayMarker = Components.Schemas.DayMarker
public typealias DayRule = Components.Schemas.DayRule
public typealias DayRulesResponse = Components.Schemas.DayRulesResponse
public typealias CaffeineToday = Components.Schemas.CaffeineToday
public typealias FastingState = Components.Schemas.FastingState
public typealias SupplementsToday = Components.Schemas.SupplementsToday
public typealias SorenessToday = Components.Schemas.SorenessToday
public typealias TrackerList = Components.Schemas.TrackerList
public typealias DayTrends = Components.Schemas.DayTrends
public typealias DayTrend = Components.Schemas.DayTrend

public extension OpenAPIObjectContainer {
    /// Builds a container from a JSON-shaped dictionary, such as a WebAuthn
    /// credential. Values must be JSON types: strings, numbers, booleans,
    /// arrays, dictionaries, or nil.
    init(json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        self = try JSONDecoder().decode(OpenAPIObjectContainer.self, from: data)
    }

    /// The container's contents as plain Foundation JSON values.
    var json: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}

public typealias ConversationSummary = Components.Schemas.ConversationSummary
public typealias ConversationDetail = Components.Schemas.ConversationDetail
public typealias ChatMessage = Components.Schemas.ChatMessage
public typealias ToolApproval = Components.Schemas.Approval
public typealias ExerciseDetail = Components.Schemas.ExerciseDetail
