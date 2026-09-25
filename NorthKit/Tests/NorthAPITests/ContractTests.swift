import Foundation
import OpenAPIRuntime
import Testing
@testable import NorthAPI

/// The web app pins every /api/v1 response shape in a golden file; these
/// tests decode each one with the types generated from openapi.yaml. A golden
/// file that fails here means the server and the spec disagree, which is the
/// bug a generated client would otherwise find in production.
struct ContractTests {
    typealias Schemas = Components.Schemas

    @Test func authResponse() throws {
        let response = try decode(Schemas.AuthResponse.self, "auth")
        #expect(response.token == "opaque-session-token")
        #expect(response.user.needsOnboarding)
    }

    @Test func me() throws {
        let response = try decode(Schemas.MeResponse.self, "me")
        #expect(response.user.email == "ana@example.com")
    }

    @Test func onboarding() throws {
        let response = try decode(Schemas.OnboardingResponse.self, "onboarding")
        #expect(response.threadId != nil)
    }

    @Test func today() throws {
        let response = try decode(Schemas.TodayResponse.self, "today")
        #expect(response.snapshot.goals.first?.progress == 40)
        #expect(response.snapshot.sleep.quality == 4)
        #expect(response.snapshot.nudges.count == 1)
    }

    @Test func passkeyCeremony() throws {
        let response = try decode(Schemas.PasskeyCeremonyResponse.self, "passkey-ceremony")
        #expect(response.challengeId == "66666666-6666-6666-6666-666666666666")
    }

    @Test func captureParse() throws {
        let response = try decode(Schemas.ParseResponse.self, "parse")
        #expect(response.items.count == 3)
    }

    @Test func captureCommit() throws {
        let response = try decode(Schemas.CommitResponse.self, "commit")
        #expect(response.written == 1)
    }

    @Test func conversation() throws {
        let detail = try decode(Schemas.ConversationDetail.self, "conversation")
        // The tool plumbing turn is left out on the server: question, answer.
        #expect(detail.messages.map(\.role) == [.user, .coach])
        #expect(detail.messages.last?.exercises == ["push-up"])
        #expect(detail.pendingApproval?.calls.first?.name == "log_check_in")
    }

    @Test func conversations() throws {
        let list = try decode(Schemas.ConversationList.self, "conversations")
        #expect(list.conversations.map(\.kind) == [.chat, .reflection])
        #expect(list.conversations.last?.ended == true)
    }

    @Test func exercise() throws {
        let exercise = try decode(Schemas.ExerciseDetail.self, "exercise")
        #expect(exercise.art?.frames.count == 3)
        #expect(exercise.art?.size == 512)
        #expect(exercise.art?.credit.contains("CC BY-SA") == true)
    }

    @Test func settings() throws {
        #expect(try decode(Schemas.Profile.self, "profile").coachingTone == .direct)
        #expect(try decode(Schemas.NotificationSettings.self, "notifications").statsDigestCadence == .weekly)
        let ai = try decode(Schemas.AISettings.self, "ai-settings")
        #expect(ai.current?.keyHint == "…9f2c")
        #expect(try decode(Schemas.ConnectionList.self, "connections").connections.first?.kind == .claudeCode)
        #expect(try decode(Schemas.CreatedConnection.self, "connection-created").token.hasPrefix("nk_"))
        #expect(try decode(Schemas.ActivityList.self, "activity").executions.first?.outcome == .executed)
        #expect(try decode(Schemas.TelegramSettings.self, "telegram").linked)
        #expect(try decode(Schemas.CalendarSettings.self, "calendar").connected?.status == "ok")
    }

    @Test func training() throws {
        let plan = try decode(Schemas.PlanDetail.self, "plan")
        #expect(plan.days.first?.startTime == "07:00")
        #expect(plan.days.last?.startTime == nil)
        #expect(plan.days.first?.exercises.first?.hasArt == true)
        #expect(try decode(Schemas.PlanList.self, "plans").plans.first?.days.count == 2)
        #expect(try decode(Schemas.ExerciseList.self, "exercises").total == 42)
        let activity = try decode(Schemas.ActivityOverview.self, "activity-overview")
        #expect(activity.active?.status == .paused)
        #expect(activity.recent.first?.caloriesBurned == 212.5)
    }

    @Test func healthStravaAndInsights() throws {
        let sync = try decode(Schemas.HealthSyncResult.self, "health-sync")
        #expect(sync.readings == 1240 && sync.workouts == 3)
        let strava = try decode(Schemas.StravaStatus.self, "strava-status")
        #expect(strava.connected && !strava.syncPending && strava.lastSyncedAt != nil)
        #expect(try decode(Schemas.StravaConnect.self, "strava-connect").authorizeUrl.hasPrefix("https://www.strava.com/"))
        let summary = try decode(Schemas.InsightsSummary.self, "insights-summary")
        #expect(summary.scores.first?.components.first?.earned == 30)
        #expect(summary.pinned.first?.metricKey == "sleep")
        #expect(summary.pinned.first?.chart?.series.first?.values == [7.2, 6.8, 7.9])
        let metric = try decode(Schemas.InsightMetric.self, "insights-metric")
        #expect(metric.trend.word == "up" && metric.comparison.priorPct == 96)
        #expect(metric.range.options.map(\.key) == ["week", "month"])
    }

    @Test func goalsAndCheckIns() throws {
        let list = try decode(Schemas.GoalList.self, "goals")
        #expect(list.goals.first?.status == .active)
        #expect(list.goals.first?.latestUpdate?.progress == 40)
        #expect(list.categories.contains("fitness"))
        let goal = try decode(Schemas.GoalDetail.self, "goal")
        #expect(goal.value1.targetDate == "2026-12-06")
        #expect(goal.value2.milestones.map(\.status) == [.completed, .open])
        let checkIns = try decode(Schemas.CheckInList.self, "check-ins")
        #expect(checkIns.today?.relatedGoalTitle == "Run a half marathon")
        #expect(checkIns.streak == 6)
    }

    @Test func reportsAndMemories() throws {
        let reports = try decode(Schemas.ReportList.self, "reports")
        #expect(reports.reports.first?.kind == .weekly && reports.reports.first?.helpful == true)
        let report = try decode(Schemas.ReportDetail.self, "report")
        #expect(report.value2.body.hasPrefix("## The week"))
        let memories = try decode(Schemas.MemoryList.self, "memories")
        #expect(memories.pending.first?.status == .pending)
        #expect(memories.approved.first?.pinned == true)
        #expect(memories.categories.contains("injury"))
    }

    @Test func knowledgeAndFormChecks() throws {
        let library = try decode(Schemas.KnowledgeList.self, "knowledge")
        #expect(library.documents.first?.status == .ready && library.counts.ready == 1)
        let document = try decode(Schemas.KnowledgeDocumentDetail.self, "knowledge-document")
        #expect(document.value2.text.hasPrefix("# Marathon plan"))
        let search = try decode(Schemas.KnowledgeSearchResults.self, "knowledge-search")
        #expect(search.hits.first?.headingPath == ["Marathon plan"])
        #expect(search.hits.first?.segments.filter(\.matched).map(\.text) == ["easy runs"])
        let checks = try decode(Schemas.FormCheckList.self, "form-checks")
        #expect(checks.checks.first?.result?.issues.first?.at == 4.5)
        #expect(try decode(Schemas.FormCheck.self, "form-check").status == .running)
    }

    @Test func phase6() throws {
        let care = try decode(Schemas.Care.self, "care")
        #expect(care.water.totalMl == 1250 && care.lastNight?.quality == 4)
        #expect(care.habits.first?.daysOfWeek == [1, 3, 5] && care.reminders.first?.due == true)
        let journal = try decode(Schemas.Journal.self, "journal")
        #expect(journal.entries.first?.mood == 4 && journal.trend.count == 9)
        #expect(try decode(Schemas.IngredientList.self, "nutrition-ingredients").ingredients.first?.own == false)
        #expect(try decode(Schemas.MealPlanList.self, "nutrition-plans").plans.first?.mealCount == 1)
        let plan = try decode(Schemas.MealPlanDetail.self, "nutrition-plan")
        #expect(plan.value2.meals.first?.ingredients.first?.quantityGrams == 80)
        let log = try decode(Schemas.FoodLog.self, "nutrition-log")
        #expect(log.progress?.goal.calories == 2200 && log.entries.first?.quantityGrams == 80)
        #expect(try decode(Schemas.DecisionList.self, "decisions").decisions.first?.outcome == "")
        let bell = try decode(Schemas.NudgeList.self, "nudges")
        #expect(bell.unread == 1 && bell.nudges.first?.href == "/app/check-ins")
        let calculator = try decode(Schemas.Calculator.self, "calculator")
        #expect(calculator.biometrics?.weightKg == 72 && calculator.goal?.calorieGoal == 2274)
        #expect(calculator.options.goals.contains("maintenance"))
        #expect(try decode(Schemas.NewsTicker.self, "news").items.first?.source == "BBC Health")
    }

    @Test func phase8a() throws {
        let timeline = try decode(Schemas.InsightsTimeline.self, "insights-timeline")
        #expect(timeline.entries.first?.kind == "check_in" && timeline.filters.first?.selected == true)
        let body = try decode(Schemas.InsightsBody.self, "insights-body")
        #expect(body.adherence == 71 && body.habits.first?.streak == 3 && body.avgSleepMinutes == 438)
        let mind = try decode(Schemas.InsightsMind.self, "insights-mind")
        #expect(mind.mood == [4, 0, 3] && mind.labels.count == mind.energy.count)
        let progress = try decode(Schemas.InsightsProgress.self, "insights-progress")
        #expect(progress.statuses.map(\.label) == ["Active", "Achieved"] && progress.goals.first?.progress == 60)
        let training = try decode(Schemas.InsightsTraining.self, "insights-training")
        #expect(training.kinds.first?.value == 1 && training.delta.hasPrior)
        let nutrition = try decode(Schemas.InsightsNutrition.self, "insights-nutrition")
        #expect(nutrition.macros.map(\.label) == ["Protein", "Fat", "Carbs"] && nutrition.hasGoal)
        #expect(try decode(Schemas.InsightsCoach.self, "insights-coach").helpfulRate == 80)
        #expect(try decode(Schemas.InsightsSpend.self, "insights-spend").surfaces.first?.pct == 75)
        let played = try decode(Schemas.FormCheck.self, "form-check-playback")
        #expect(played.playbackUrl?.hasPrefix("https://") == true)
        let diets = try decode(Schemas.DietSettings.self, "diets")
        #expect(diets.diets.filter(\.selected).map(\.code) == ["vegetarian"])
    }

    /// Every golden file the sync script copied has a test above.
    @Test func everyGoldenFileIsDecoded() throws {
        let covered: Set = ["auth", "me", "onboarding", "today", "passkey-ceremony", "parse", "commit",
                            "conversation", "conversations", "exercise",
                            "profile", "notifications", "ai-settings", "connections", "connection-created",
                            "activity", "telegram", "calendar",
                            "plan", "plans", "exercises", "activity-overview",
                            "health-sync", "strava-status", "strava-connect", "insights-summary", "insights-metric",
                            "goals", "goal", "check-ins", "reports", "report", "memories",
                            "knowledge", "knowledge-document", "knowledge-search", "form-checks", "form-check",
                            "care", "journal", "nutrition-ingredients", "nutrition-plans", "nutrition-plan", "nutrition-log",
                            "decisions", "nudges", "calculator", "news",
                            "insights-timeline", "insights-body", "insights-mind", "insights-progress",
                            "insights-training", "insights-nutrition", "insights-coach", "insights-spend",
                            "form-check-playback", "diets"]
        let names = try FileManager.default.contentsOfDirectory(at: contractDirectory, includingPropertiesForKeys: nil)
            .map { $0.lastPathComponent.replacingOccurrences(of: ".golden.json", with: "") }
        #expect(Set(names) == covered, "add a decode test for each new golden file")
    }

    private var contractDirectory: URL {
        Bundle.module.resourceURL!.appending(path: "Contract")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let data = try Data(contentsOf: contractDirectory.appending(path: "\(name).golden.json"))
        let decoder = JSONDecoder()
        let transcoder = NorthAPI.configuration.dateTranscoder
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            return try transcoder.decode(raw)
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct DateTranscoderTests {
    let transcoder = FlexibleISO8601DateTranscoder()

    @Test(arguments: [
        "2026-09-24T07:15:00Z",
        "2026-09-24T07:15:00.5Z",
        "2026-09-24T07:15:00.123Z",
        "2026-09-24T07:15:00.123456789Z",
        "2026-09-24T08:15:00.123456789+01:00",
    ])
    func readsWhatGoWrites(_ raw: String) throws {
        let date = try transcoder.decode(raw)
        let expected = try transcoder.decode("2026-09-24T07:15:00Z")
        #expect(abs(date.timeIntervalSince(expected)) < 1)
    }

    @Test func roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        #expect(try transcoder.decode(transcoder.encode(date)) == date)
    }
}
