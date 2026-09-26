import Foundation
import NorthAPI

typealias InsightsTimeline = Components.Schemas.InsightsTimeline
typealias InsightsBody = Components.Schemas.InsightsBody
typealias InsightsMind = Components.Schemas.InsightsMind
typealias InsightsProgress = Components.Schemas.InsightsProgress
typealias InsightsTraining = Components.Schemas.InsightsTraining
typealias InsightsNutrition = Components.Schemas.InsightsNutrition
typealias InsightsCoach = Components.Schemas.InsightsCoach
typealias InsightsSpend = Components.Schemas.InsightsSpend
typealias InsightsSegment = Components.Schemas.InsightsSegment

/// The pages behind each area on the Progress tab, the same ones the web
/// shows under Insights.
protocol InsightsDomainServicing: Sendable {
    func timeline(kind: String?, range: String?) async throws -> InsightsTimeline
    func body(range: String?) async throws -> InsightsBody
    func mind(range: String?) async throws -> InsightsMind
    func progress(range: String?) async throws -> InsightsProgress
    func training(range: String?) async throws -> InsightsTraining
    func nutrition(range: String?) async throws -> InsightsNutrition
    func coach(range: String?) async throws -> InsightsCoach
    func spend(range: String?) async throws -> InsightsSpend
}

extension InsightsService: InsightsDomainServicing {
    func timeline(kind: String?, range: String?) async throws -> InsightsTimeline {
        try await NorthAPI.call { try await api.getInsightsTimeline(query: .init(range: range, kind: kind)).ok.body.json }
    }

    func body(range: String?) async throws -> InsightsBody {
        try await NorthAPI.call { try await api.getInsightsBody(query: .init(range: range)).ok.body.json }
    }

    func mind(range: String?) async throws -> InsightsMind {
        try await NorthAPI.call { try await api.getInsightsMind(query: .init(range: range)).ok.body.json }
    }

    func progress(range: String?) async throws -> InsightsProgress {
        try await NorthAPI.call { try await api.getInsightsProgress(query: .init(range: range)).ok.body.json }
    }

    func training(range: String?) async throws -> InsightsTraining {
        try await NorthAPI.call { try await api.getInsightsTraining(query: .init(range: range)).ok.body.json }
    }

    func nutrition(range: String?) async throws -> InsightsNutrition {
        try await NorthAPI.call { try await api.getInsightsNutrition(query: .init(range: range)).ok.body.json }
    }

    func coach(range: String?) async throws -> InsightsCoach {
        try await NorthAPI.call { try await api.getInsightsCoach(query: .init(range: range)).ok.body.json }
    }

    func spend(range: String?) async throws -> InsightsSpend {
        try await NorthAPI.call { try await api.getInsightsSpend(query: .init(range: range)).ok.body.json }
    }
}

/// Every insights page the Progress tab can open. The first five match the
/// score keys the summary returns, so a score row opens its own page.
enum InsightsDomain: String, CaseIterable, Identifiable, Hashable {
    case body, mind, progress, training, nutrition, sleep, cardio, patterns, timeline, coach, spend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: "Body"
        case .mind: "Mind"
        case .progress: "Goals"
        case .training: "Training"
        case .nutrition: "Nutrition"
        case .sleep: "Sleep"
        case .cardio: "Cardio"
        case .patterns: "Patterns"
        case .timeline: "Timeline"
        case .coach: "Coach"
        case .spend: "AI Spend"
        }
    }

    var systemImage: String {
        switch self {
        case .body: "drop"
        case .mind: "brain.head.profile"
        case .progress: "flag"
        case .training: "figure.run"
        case .nutrition: "fork.knife"
        case .sleep: "moon.zzz"
        case .cardio: "figure.run.circle"
        case .patterns: "sparkles"
        case .timeline: "list.bullet.below.rectangle"
        case .coach: "bubble.left.and.bubble.right"
        case .spend: "eurosign.circle"
        }
    }
}
