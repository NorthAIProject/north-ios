import Foundation

public struct TodayResponseDTO: Sendable, Equatable {
    let user: UserDTO
    let snapshot: TodaySnapshotDTO
}

public struct TodaySnapshotDTO: Sendable, Equatable {
    let range: String
    let checkedInToday: Bool
    let streak: Int
    let goalActivity7d: Int
    let pendingMemories: Int
    let goals: [TodayGoalDTO]
    let lastThread: TodayThreadDTO?
    let nextStep: TodayNextStepDTO?
    let hydration: TodayHydrationDTO
    let sleep: TodaySleepDTO
    let activityCalories: Double
    let timeline: [TodayTimelineDTO]
    let deltas: TodayDeltasDTO
    let nudges: [TodayNudgeDTO]
    let briefing: String?
}

public struct TodayGoalDTO: Sendable, Equatable {
    let id: String
    let title: String
    let category: String
    let status: String
    let targetDate: Date?
    let milestoneTotal: Int
    let milestoneDone: Int
    let progress: Int?
}

public struct TodayThreadDTO: Sendable, Equatable {
    let id: String
    let title: String
    let kind: String
    let updatedAt: Date
}

public struct TodayNextStepDTO: Sendable, Equatable {
    let kind: String
    let eyebrow: String
    let title: String
    let body: String
    let cta: String
    let href: String
}

public struct TodayHydrationDTO: Sendable, Equatable {
    let todayML: Int
    let targetML: Int
    let percent: Int
}

public struct TodaySleepDTO: Sendable, Equatable {
    let logged: Bool
    let durationMinutes: Int
    let quality: Int?
}

public struct TodayTimelineDTO: Sendable, Equatable {
    let kind: String
    let label: String
    let at: Date
    let title: String
    let detail: String?
    let href: String?
    let icon: String
}

public struct TodayDeltasDTO: Sendable, Equatable {
    let hydration: TodayDeltaDTO
    let sleepHours: TodayDeltaDTO
    let calories: TodayDeltaDTO
    let checkIns: TodayDeltaDTO
}

public struct TodayDeltaDTO: Sendable, Equatable {
    let pct: Double
    let direction: Int
    let hasPrior: Bool
}

public struct TodayNudgeDTO: Sendable, Equatable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let href: String
    let createdAt: Date
}

extension TodayResponseDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(UserDTO.self, forKey: .user)
        snapshot = try container.decode(TodaySnapshotDTO.self, forKey: .snapshot)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user, forKey: .user)
        try container.encode(snapshot, forKey: .snapshot)
    }

    private enum CodingKeys: String, CodingKey { case user, snapshot }
}

extension TodaySnapshotDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decode(String.self, forKey: .range)
        checkedInToday = try c.decode(Bool.self, forKey: .checkedInToday)
        streak = try c.decode(Int.self, forKey: .streak)
        goalActivity7d = try c.decode(Int.self, forKey: .goalActivity7d)
        pendingMemories = try c.decode(Int.self, forKey: .pendingMemories)
        goals = try c.decode([TodayGoalDTO].self, forKey: .goals)
        lastThread = try c.decodeIfPresent(TodayThreadDTO.self, forKey: .lastThread)
        nextStep = try c.decodeIfPresent(TodayNextStepDTO.self, forKey: .nextStep)
        hydration = try c.decode(TodayHydrationDTO.self, forKey: .hydration)
        sleep = try c.decode(TodaySleepDTO.self, forKey: .sleep)
        activityCalories = try c.decode(Double.self, forKey: .activityCalories)
        timeline = try c.decode([TodayTimelineDTO].self, forKey: .timeline)
        deltas = try c.decode(TodayDeltasDTO.self, forKey: .deltas)
        nudges = try c.decode([TodayNudgeDTO].self, forKey: .nudges)
        briefing = try c.decodeIfPresent(String.self, forKey: .briefing)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(range, forKey: .range)
        try c.encode(checkedInToday, forKey: .checkedInToday)
        try c.encode(streak, forKey: .streak)
        try c.encode(goalActivity7d, forKey: .goalActivity7d)
        try c.encode(pendingMemories, forKey: .pendingMemories)
        try c.encode(goals, forKey: .goals)
        try c.encodeIfPresent(lastThread, forKey: .lastThread)
        try c.encodeIfPresent(nextStep, forKey: .nextStep)
        try c.encode(hydration, forKey: .hydration)
        try c.encode(sleep, forKey: .sleep)
        try c.encode(activityCalories, forKey: .activityCalories)
        try c.encode(timeline, forKey: .timeline)
        try c.encode(deltas, forKey: .deltas)
        try c.encode(nudges, forKey: .nudges)
        try c.encodeIfPresent(briefing, forKey: .briefing)
    }

    private enum CodingKeys: String, CodingKey {
        case range, checkedInToday, streak, goalActivity7d, pendingMemories, goals, lastThread, nextStep, hydration, sleep, activityCalories, timeline, deltas, nudges, briefing
    }
}

extension TodayGoalDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(String.self, forKey: .category)
        status = try c.decode(String.self, forKey: .status)
        targetDate = try c.decodeIfPresent(Date.self, forKey: .targetDate)
        milestoneTotal = try c.decode(Int.self, forKey: .milestoneTotal)
        milestoneDone = try c.decode(Int.self, forKey: .milestoneDone)
        progress = try c.decodeIfPresent(Int.self, forKey: .progress)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(category, forKey: .category); try c.encode(status, forKey: .status); try c.encodeIfPresent(targetDate, forKey: .targetDate); try c.encode(milestoneTotal, forKey: .milestoneTotal); try c.encode(milestoneDone, forKey: .milestoneDone); try c.encodeIfPresent(progress, forKey: .progress)
    }

    private enum CodingKeys: String, CodingKey { case id, title, category, status, targetDate, milestoneTotal, milestoneDone, progress }
}

extension TodayThreadDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); title = try c.decode(String.self, forKey: .title); kind = try c.decode(String.self, forKey: .kind); updatedAt = try c.decode(Date.self, forKey: .updatedAt) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(kind, forKey: .kind); try c.encode(updatedAt, forKey: .updatedAt) }
    private enum CodingKeys: String, CodingKey { case id, title, kind, updatedAt }
}

extension TodayNextStepDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); kind = try c.decode(String.self, forKey: .kind); eyebrow = try c.decode(String.self, forKey: .eyebrow); title = try c.decode(String.self, forKey: .title); body = try c.decode(String.self, forKey: .body); cta = try c.decode(String.self, forKey: .cta); href = try c.decode(String.self, forKey: .href) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(kind, forKey: .kind); try c.encode(eyebrow, forKey: .eyebrow); try c.encode(title, forKey: .title); try c.encode(body, forKey: .body); try c.encode(cta, forKey: .cta); try c.encode(href, forKey: .href) }
    private enum CodingKeys: String, CodingKey { case kind, eyebrow, title, body, cta, href }
}

extension TodayHydrationDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); todayML = try c.decode(Int.self, forKey: .todayML); targetML = try c.decode(Int.self, forKey: .targetML); percent = try c.decode(Int.self, forKey: .percent) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(todayML, forKey: .todayML); try c.encode(targetML, forKey: .targetML); try c.encode(percent, forKey: .percent) }
    private enum CodingKeys: String, CodingKey { case todayML, targetML, percent }
}

extension TodaySleepDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); logged = try c.decode(Bool.self, forKey: .logged); durationMinutes = try c.decode(Int.self, forKey: .durationMinutes); quality = try c.decodeIfPresent(Int.self, forKey: .quality) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(logged, forKey: .logged); try c.encode(durationMinutes, forKey: .durationMinutes); try c.encodeIfPresent(quality, forKey: .quality) }
    private enum CodingKeys: String, CodingKey { case logged, durationMinutes, quality }
}

extension TodayTimelineDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); kind = try c.decode(String.self, forKey: .kind); label = try c.decode(String.self, forKey: .label); at = try c.decode(Date.self, forKey: .at); title = try c.decode(String.self, forKey: .title); detail = try c.decodeIfPresent(String.self, forKey: .detail); href = try c.decodeIfPresent(String.self, forKey: .href); icon = try c.decode(String.self, forKey: .icon) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(kind, forKey: .kind); try c.encode(label, forKey: .label); try c.encode(at, forKey: .at); try c.encode(title, forKey: .title); try c.encodeIfPresent(detail, forKey: .detail); try c.encodeIfPresent(href, forKey: .href); try c.encode(icon, forKey: .icon) }
    private enum CodingKeys: String, CodingKey { case kind, label, at, title, detail, href, icon }
}

extension TodayDeltasDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); hydration = try c.decode(TodayDeltaDTO.self, forKey: .hydration); sleepHours = try c.decode(TodayDeltaDTO.self, forKey: .sleepHours); calories = try c.decode(TodayDeltaDTO.self, forKey: .calories); checkIns = try c.decode(TodayDeltaDTO.self, forKey: .checkIns) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(hydration, forKey: .hydration); try c.encode(sleepHours, forKey: .sleepHours); try c.encode(calories, forKey: .calories); try c.encode(checkIns, forKey: .checkIns) }
    private enum CodingKeys: String, CodingKey { case hydration, sleepHours, calories, checkIns }
}

extension TodayDeltaDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); pct = try c.decode(Double.self, forKey: .pct); direction = try c.decode(Int.self, forKey: .direction); hasPrior = try c.decode(Bool.self, forKey: .hasPrior) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(pct, forKey: .pct); try c.encode(direction, forKey: .direction); try c.encode(hasPrior, forKey: .hasPrior) }
    private enum CodingKeys: String, CodingKey { case pct, direction, hasPrior }
}

extension TodayNudgeDTO: Codable {
    public nonisolated init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); kind = try c.decode(String.self, forKey: .kind); title = try c.decode(String.self, forKey: .title); body = try c.decode(String.self, forKey: .body); href = try c.decode(String.self, forKey: .href); createdAt = try c.decode(Date.self, forKey: .createdAt) }
    public nonisolated func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(title, forKey: .title); try c.encode(body, forKey: .body); try c.encode(href, forKey: .href); try c.encode(createdAt, forKey: .createdAt) }
    private enum CodingKeys: String, CodingKey { case id, kind, title, body, href, createdAt }
}
