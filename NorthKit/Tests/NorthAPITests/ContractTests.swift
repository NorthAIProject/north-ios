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
        let checkIn = try #require(response.snapshot.todayCheckIn)
        #expect(checkIn.mood == 4 && checkIn.energy == 3 && checkIn.source == "siri")
        #expect(checkIn.stress == 2 && checkIn.sleepQuality == 4)
    }

    @Test func day() throws {
        let response = try decode(Schemas.DayResponse.self, "day")
        #expect(response.date == "2026-09-26")
        #expect(response.vitals.energyPercent == 32)
        #expect(response.food.goal?.calories == 2200)
        #expect(response.activity.move.percent == 100)
        #expect(response.sleep?.stages.additionalProperties["deep"] == 64)
        #expect(response.sleep?.blocks.first?.stage == .core)
        #expect(response.body.bmiCategory == .overweight)
        #expect(response.timeline.first?.kind == "food")
        #expect(response.markers.first?.kind == "kitchen_closes")
    }

    @Test func dayTrackers() throws {
        let response = try decode(Schemas.DayResponse.self, "day")
        #expect(response.level == 21)
        #expect(response.caffeine.activeMg == 72)
        #expect(response.fast?.phase == .fatBurning)
        #expect(response.nutrients.total == 3)
        #expect(response.milestones.first?.name == "Dentist")
        #expect(response.body.toGoalKg == 3.9)
        #expect(response.body.bloodPressure?.systolic == 122)
        #expect(response.body.soreness.first?.region == "quads")
        #expect(response.vitals.screenMinutes == 248)
    }

    @Test func stats() throws {
        let sleep = try decode(Schemas.StatsSleep.self, "stats_sleep")
        #expect(sleep.nights.count == 2)
        #expect(sleep.stageShare.additionalProperties["deep"] != nil)
        let cardio = try decode(Schemas.StatsCardio.self, "stats_cardio")
        #expect(cardio.runs.best5kSeconds == 1500)
        #expect(cardio.restingHeartRate.count == 2)
        let eating = try decode(Schemas.StatsEating.self, "stats_eating")
        #expect(eating.lateDays == 1)
        #expect(eating.bySlot.count == 5)
        let patterns = try decode(Schemas.StatsPatterns.self, "stats_patterns")
        #expect(patterns.findings.first?.a.days == 8)
    }

    @Test func lifts() throws {
        let stats = try decode(Schemas.LiftStats.self, "lift_stats")
        #expect(stats.volumeKg == 1025)
        #expect(stats.records.first?.e1rmKg == 122.5)
        #expect(stats.exercises.first?.trend.count == 1)
        let last = try decode(Schemas.LiftLast.self, "lift_last")
        #expect(last.exercises.first?.sets.map(\.setNumber) == [1, 2])
        let recap = try decode(Schemas.LiftRecap.self, "lift_recap")
        #expect(recap.setsPrescribed == 6 && recap.planWeekday == "Thursday")
        #expect(recap.exercises.first?.changeE1rmKg == 5.8 && recap.exercises.first?.previousVolumeKg == 975)
    }

    @Test func trackers() throws {
        #expect(try decode(Schemas.CaffeineToday.self, "caffeine").entries.first?.mg == 100)
        #expect(try decode(Schemas.FastingState.self, "fasting").current?.phase == .fatBurning)
        #expect(try decode(Schemas.SupplementsToday.self, "supplements").entries.first?.count == 3)
        #expect(try decode(Schemas.ScreenTimeDay.self, "screen_time").minutes == 248)
        #expect(try decode(Schemas.SorenessToday.self, "soreness").regions.contains("quads"))
        #expect(try decode(Schemas.TrackerList.self, "trackers").trackers.first?.due == true)
    }

    @Test func dayTrends() throws {
        let trends = try decode(Schemas.DayTrends.self, "day_trends")
        #expect(trends.series.first?.key == .systolic)
        #expect(trends.series.first?.headline == 122)
        #expect(trends.fasts.first?.met == true)
    }

    @Test func dayRules() throws {
        let response = try decode(Schemas.DayRulesResponse.self, "day_rules")
        #expect(response.rules.first?.at == "20:00")
        #expect(response.kinds.contains("screens_off"))
    }

    @Test func passkeyCeremony() throws {
        let response = try decode(Schemas.PasskeyCeremonyResponse.self, "passkey-ceremony")
        #expect(response.challengeId == "66666666-6666-6666-6666-666666666666")
    }

    @Test func captureParse() throws {
        let response = try decode(Schemas.ParseResponse.self, "parse")
        #expect(response.items.count == 3)
    }

    @Test func captureFoods() throws {
        let draft = try decode(Schemas.FoodDraft.self, "foods")
        #expect(draft.lines.count == 3)
        #expect(draft.lines[0].ingredientId == "11111111-1111-1111-1111-111111111111")
        #expect(draft.lines[1].ingredientId == nil)
        #expect(draft.lines[2].candidates.isEmpty)
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

    @Test func chatAttachment() throws {
        let attachment = try decode(Schemas.ChatAttachment.self, "chat_attachment")
        #expect(attachment.kind == "file" && attachment.mimeType == "application/pdf")
        #expect(attachment.name == "dieta.pdf")
    }

    @Test func mealPlanWithOptions() throws {
        let plan = try decode(Schemas.MealPlanDetail.self, "nutrition-plan-with-options")
        #expect(plan.value2.notes == "Beber 2 L de água por dia.")
        let meal = try #require(plan.value2.days.first?.meals.first)
        #expect(meal.optionLabel == "Opção 1" && meal.alternatives?.count == 1)
        let alternative = try #require(meal.alternatives?.first)
        #expect(alternative.optionLabel == "Opção 2" && alternative.totalMacros.calories == 206)
        #expect(alternative.ingredients.first?.sourceText == "peixe branco à vontade")
        #expect(alternative.ingredients.first?.estimated == true)
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
        let notifications = try decode(Schemas.NotificationSettings.self, "notifications")
        #expect(notifications.statsDigestCadence == .weekly)
        #expect(notifications.briefingHour == 7 && notifications.eveningReflection && notifications.eveningHour == 21)
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
        #expect(try decode(Schemas.PlanList.self, "plans").plans.first?.active == true)
        let week = try decode(Schemas.TrainingWeek.self, "week")
        #expect(week.days.map(\.weekday) == ["Monday", "Thursday"])
        #expect(week.days.first?.completed == true)
        #expect(week.next?.dayIndex == 1 && week.next?.isNext == true)
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
        #expect(metric.health == nil && metric.usual == nil)
        let healthMetric = try decode(Schemas.InsightMetric.self, "insights-metric-health")
        #expect(healthMetric.health == true && healthMetric.usual?.state == "above")
        #expect(healthMetric.usual?.low == "7900" && healthMetric.usual?.days == 28)
        let health = try decode(Schemas.InsightsHealth.self, "insights-health")
        #expect(health.metrics.map(\.key) == ["steps", "vo2max"])
        #expect(health.metrics.first?.recent == [8800, 11200] && health.metrics.first?.usual?.z == 2)
        #expect(health.metrics.last?.usual == nil && health.metrics.last?.latest == "44.2")
        let recovery = try decode(Schemas.InsightsRecovery.self, "insights-recovery")
        #expect(recovery.hasData && recovery.points == 0 && recovery.verdict == "low")
        #expect(recovery.signals.first?.key == "hrv" && recovery.signals.first?.latest == "38ms")
        #expect(recovery.hasData && recovery.verdict == "low" && recovery.label == "Under your usual")
        #expect(recovery.signals.map(\.key) == ["hrv", "resting-heart-rate", "sleep"])
        #expect(recovery.signals.first?.usual.state == "below" && recovery.sentence.hasPrefix("Recovery today: "))
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
        #expect(checkIns.today?.source == "siri" && checkIns.today?.tags == ["travel", "race week"])
        #expect(checkIns.today?.stress == 2 && checkIns.today?.sleepQuality == 4)
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
        let plans = try decode(Schemas.MealPlanList.self, "nutrition-plans").plans
        #expect(plans.first?.planType == .highCarb && plans.first?.mode == .advanced && plans.first?.dayCount == 2)
        let plan = try decode(Schemas.MealPlanDetail.self, "nutrition-plan")
        let monday = plan.value2.days.first
        #expect(monday?.weekday == 1 && monday?.carbType == .lowCarb && monday?.status?.isOver == true)
        #expect(monday?.status?.remaining.carbG == -13.9 && plan.value2.days.last?.status == nil)
        #expect(monday?.meals.first?.ingredients.first?.quantityGrams == 80)
        let options = try decode(Schemas.MealPlanOptions.self, "nutrition-plan-options")
        #expect(options.planTypes.map(\.id) == [.midCarb, .custom] && options.planTypes.last?.advancedOnly == true)
        let over = try decode(Schemas.MacroOverage.self, "nutrition-overage")
        #expect(over.canConfirm && over.days.first?.over.carbG == 13.9)
        #expect(try decode(Schemas.MealPortionList.self, "nutrition-portions").portions.count == 1)
        let log = try decode(Schemas.FoodLog.self, "nutrition-log")
        #expect(log.progress?.goal.calories == 2200 && log.entries.first?.quantityGrams == 80)
        #expect(try decode(Schemas.DecisionList.self, "decisions").decisions.first?.outcome == "March. The knee held up.")
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
        #expect(training.plan == nil && training.recap == nil, "no plan, no recap: both absent")
        let planned = try decode(Schemas.InsightsTraining.self, "insights-training-plan")
        #expect(planned.plan?.days.map(\.done) == [true, false, false] && planned.plan?.days[1].today == true)
        #expect(planned.recap?.sentence.hasPrefix("40 minutes") == true)
        let nutrition = try decode(Schemas.InsightsNutrition.self, "insights-nutrition")
        #expect(nutrition.macros.map(\.label) == ["Protein", "Fat", "Carbs"] && nutrition.hasGoal)
        #expect(try decode(Schemas.InsightsCoach.self, "insights-coach").helpfulRate == 80)
        #expect(try decode(Schemas.InsightsSpend.self, "insights-spend").surfaces.first?.pct == 75)
        let played = try decode(Schemas.FormCheck.self, "form-check-playback")
        #expect(played.playbackUrl?.hasPrefix("https://") == true)
        let diets = try decode(Schemas.DietSettings.self, "diets")
        #expect(diets.diets.filter(\.selected).map(\.code) == ["vegetarian"])
    }

    @Test func social() throws {
        let overview = try decode(Schemas.SocialOverview.self, "social")
        #expect(overview.invite.url.hasSuffix("/i/k7m2p9qx4r") && overview.joined == 2)
        #expect(overview.requests.first?.value2.status == .pending && overview.requests.first?.value1.handle == "")
        #expect(overview.followers.first?.value1.handle == "ana_runs")
        #expect(try decode(Schemas.InviteView.self, "invite").channel == "link")
        #expect(try decode(Schemas.InvitePreview.self, "invite-preview").inviter.displayName == "Ana")
        let profile = try decode(Schemas.ProfileView.self, "public-profile")
        #expect(profile.value2.followers == 12 && profile.value2.relationship.following == "pending" && profile.value2.relationship.followsYou)
        #expect(try decode(Schemas.ConnectionView.self, "connection").value2.status == .pending)
        #expect(try decode(Schemas.RedeemView.self, "redeem").redeemed)
        #expect(try decode(Schemas.HandleView.self, "handle").handle == "ana_runs")
        let matches = try decode(Schemas.ContactMatches.self, "contacts-match").people
        #expect(matches.first?.value1.handle == "ana_runs" && matches.first?.value2.following == "")
        #expect(matches.last?.value2.following == "pending")
    }

    @Test func friendFinding() throws {
        let phone = try decode(Schemas.PhoneView.self, "phone")
        #expect(phone.configured && phone.number == "+351912345678" && phone.verifiedAt != nil && phone.pending == "")
        let pending = try decode(Schemas.PhoneView.self, "phone-pending")
        #expect(pending.number == "" && pending.verifiedAt == nil && pending.pending == "+447911123456")
        let facebook = try decode(Schemas.FacebookFriends.self, "facebook-friends")
        #expect(facebook.configured && facebook.connected && facebook.importedAt != nil)
        #expect(facebook.people.first?.value1.handle == "ana_runs" && facebook.people.first?.value2.following == "")
        #expect(facebook.people.last?.value2.following == "accepted")
        let off = try decode(Schemas.FacebookFriends.self, "facebook-unconfigured")
        #expect(!off.configured && !off.connected && off.people.isEmpty && off.importedAt == nil)
        let connect = try decode(Schemas.FacebookConnect.self, "facebook-connect")
        #expect(connect.authorizeUrl.hasPrefix("https://www.facebook.com/") && connect.authorizeUrl.contains("&state="))
    }

    @Test func feed() throws {
        let feed = try decode(Schemas.Feed.self, "feed")
        #expect(feed.items.first?.category == .training && feed.items.first?.kudos == 3 && feed.items.first?.kudoed == true)
        #expect(feed.before == nil)
        let sharing = try decode(Schemas.Sharing.self, "sharing")
        #expect(sharing.training && !sharing.streaks && sharing.goals && sharing.xp == true)
    }

    @Test func crews() throws {
        let list = try decode(Schemas.CrewList.self, "crews")
        #expect(list.crews.first?.joinUrl.hasSuffix("/i/c/q8w3n5k2ht") == true)
        #expect(try decode(Schemas.Crew.self, "crew").memberCount == 2)
        let board = try decode(Schemas.CrewBoard.self, "crew-board")
        #expect(board.value2.challenge?.kind == .checkins && board.value2.challenge?.target == 5)
        #expect(board.value2.members.first?.me == true && board.value2.members.first?.weekProgress == 3)
        #expect(board.value2.isOwner && board.value1.name == "Morning runners")
    }

    @Test func decisionRevisits() throws {
        let list = try decode(Schemas.DecisionList.self, "decisions")
        #expect(list.decisions.first?.held == .yes)
        let calibration = try decode(Schemas.DecisionCalibration.self, "decision-calibration")
        #expect(calibration.revisited == 7 && calibration.partly == 2)
    }

    @Test func inbox() throws {
        let inbox = try decode(Schemas.Inbox.self, "inbox")
        #expect(inbox.open == 2 && inbox.items.first?.suggestion?.destination.rawValue == "goal_note")
        #expect(try decode(Schemas.InboxItem.self, "inbox-item").suggestion == nil)
    }

    @Test func areas() throws {
        let areas = try decode(Schemas.InsightsAreas.self, "insights-areas")
        #expect(areas.weeks.count == 2 && areas.areas.first?.trend.count == 2)
        #expect(areas.focus.first == "Priorities: Three runs")
    }

    @Test func lighterDay() throws {
        let day = try decode(Schemas.LighterDay.self, "today-lighter")
        #expect(day.offered && day.readiness.low && day.readiness.hrv == 38)
        #expect(day.readiness.reason?.hasPrefix("Heart rate variability is below your usual") == true)
        #expect(day.session == "Lower body" && day.choice == nil)
    }

    @Test func weekly() throws {
        let review = try decode(Schemas.WeeklyReview.self, "weekly-review")
        #expect(review.planning == "2026-10-05" && review.report?.ready == true)
        #expect(review.goals.first?.priority == 1 && review.last?.volume == .hold)
        let focus = try decode(Schemas.WeeklyFocus.self, "weekly-focus")
        #expect(focus.volume == .deload && focus.priorities.count == 2)
    }


    @Test func xp() throws {
        let summary = try decode(Schemas.XPSummary.self, "summary")
        #expect(summary.total == 340 && summary.weekTotal == 65)
        #expect(summary.level.number == 3 && summary.level.floor == 300 && summary.level.next == 800)
        // earned has every kind; the deprecated week keeps only the first five.
        #expect(summary.earned.map(\.kind) == ["workout", "habit_kept", "week_reviewed"])
        #expect(summary.earned.first?.points == 40 && summary.earned.last?.points == 25)
        let board = try decode(Schemas.Leaderboard.self, "board")
        #expect(board.metric == .xp && board.period == .week && board.sharing)
        #expect(board.entries.first?.level?.title == "Relentless" && board.entries.first?.level?.next == nil)
        #expect(board.entries.last?.me == true && board.entries.last?.level == nil && board.entries.last?.handle == "")
    }

    @Test func bodyMap() throws {
        let map = try decode(Schemas.BodyMap.self, "body_map")
        #expect(map.days == 7 && map.lastSessionOn != nil)
        #expect(map.muscles.count == 15 && map.muscles.allSatisfy { (0...1).contains($0.intensity) })
        #expect(map.muscles.first { $0.id == "quads" }?.lastTrainedOn != nil)
    }

    /// Every golden file the sync script copied has a test above.
    @Test func everyGoldenFileIsDecoded() throws {
        let covered: Set = ["auth", "me", "onboarding", "today", "day", "day_rules", "day_trends", "caffeine", "lift_stats", "lift_last", "lift_recap", "body_map", "stats_sleep", "stats_cardio", "stats_eating", "stats_patterns", "fasting", "supplements", "screen_time", "soreness", "trackers", "passkey-ceremony", "parse", "commit", "foods",
                            "conversation", "conversations", "chat_attachment", "exercise",
                            "profile", "notifications", "ai-settings", "connections", "connection-created",
                            "activity", "telegram", "calendar",
                            "plan", "plans", "week", "exercises", "activity-overview",
                            "health-sync", "strava-status", "strava-connect", "insights-summary", "insights-metric", "insights-metric-health", "insights-health", "insights-recovery",
                            "goals", "goal", "check-ins", "reports", "report", "memories",
                            "knowledge", "knowledge-document", "knowledge-search", "form-checks", "form-check",
                            "care", "journal", "nutrition-ingredients", "nutrition-plans", "nutrition-plan", "nutrition-log",
                            "nutrition-plan-options", "nutrition-plan-with-options", "nutrition-overage", "nutrition-portions",
                            "decisions", "nudges", "calculator", "news",
                            "insights-timeline", "insights-body", "insights-mind", "insights-progress",
                            "insights-training", "insights-training-plan", "insights-nutrition", "insights-coach", "insights-spend",
                            "form-check-playback", "diets",
                            "social", "invite", "invite-preview", "public-profile", "connection", "redeem", "handle", "contacts-match", "phone", "phone-pending", "facebook-friends", "facebook-unconfigured", "facebook-connect", "feed", "sharing", "crews", "crew", "crew-board", "summary", "board",
                            "weekly-review", "weekly-focus",
                            "decision-calibration", "inbox", "inbox-item", "insights-areas", "today-lighter"]
        let names = try FileManager.default.contentsOfDirectory(at: contractDirectory, includingPropertiesForKeys: nil)
            .map { $0.lastPathComponent.replacingOccurrences(of: ".golden.json", with: "") }
        #expect(Set(names) == covered, "add a decode test for each new golden file")
    }

    private var contractDirectory: URL {
        Bundle.module.resourceURL!.appending(path: "Contract")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try decode(type, data: Data(contentsOf: contractDirectory.appending(path: "\(name).golden.json")))
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        let decoder = JSONDecoder()
        let transcoder = NorthAPI.configuration.dateTranscoder
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            return try transcoder.decode(raw)
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// Variations on a golden file: the shapes the server may also send.
extension ContractTests {
    /// A day without a check-in leaves `todayCheckIn` out, and so does an
    /// older server; both must still decode.
    @Test func todayWithoutCheckIn() throws {
        var json = try golden("today")
        var snapshot = try #require(json["snapshot"] as? [String: Any])
        snapshot["todayCheckIn"] = nil
        snapshot["checkedInToday"] = false
        json["snapshot"] = snapshot
        let response = try decode(Schemas.TodayResponse.self, from: json)
        #expect(response.snapshot.todayCheckIn == nil)
        #expect(!response.snapshot.checkedInToday)
    }

    /// Stress and sleep quality are optional; source stays an open string so
    /// a value this build has never seen still decodes.
    @Test func checkInWithoutOptionalMetadata() throws {
        let json = try golden("check-ins")
        var recent = try #require(json["recent"] as? [[String: Any]])
        recent[0]["stress"] = nil
        recent[0]["sleepQuality"] = nil
        recent[0]["tags"] = [String]()
        recent[0]["source"] = "telepathy"
        let checkIn = try decode(Schemas.CheckIn.self, from: recent[0])
        #expect(checkIn.stress == nil && checkIn.sleepQuality == nil)
        #expect(checkIn.tags.isEmpty && checkIn.source == "telepathy")
    }

    /// A golden file as a dictionary, for tests that decode a variation of it.
    private func golden(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: contractDirectory.appending(path: "\(name).golden.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) throws -> T {
        try decode(type, data: JSONSerialization.data(withJSONObject: json))
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
