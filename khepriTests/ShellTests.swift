import Foundation
import NorthAPI
import Testing
@testable import khepri

@MainActor
struct WizardTests {
    @Test func eachStepWaitsForItsAnswer() async {
        let model = WizardModel(user: .fixture, auth: FakeAuth(), defaults: .ephemeral())
        _ = await model.advance()                       // welcome
        #expect(model.step == .focusAreas)
        #expect(!model.canContinue)

        model.toggle(.fitness)
        _ = await model.advance()
        #expect(model.step == .coachingStyle)

        model.choose(.custom)
        model.setCustomStyle("short")                   // server wants 8+ characters
        #expect(!model.canContinue)
        model.setCustomStyle("blunt, but ask first")
        #expect(model.canContinue)
    }

    @Test func leavingTheGoalStepSendsTheAnswersOnce() async {
        let auth = FakeAuth()
        let model = await WizardModel.atGoal(auth: auth)

        _ = await model.advance()
        #expect(model.step == .health)
        #expect(auth.onboardingCalls.count == 1)
        #expect(auth.onboardingCalls.first?.focusAreas == ["fitness"])
        #expect(auth.onboardingCalls.first?.nearTermGoal == "Run a half marathon")
        #expect(!model.canGoBack, "answers are with the server; going back would imply they can still change here")

        _ = await model.advance()                       // health
        let user = await model.advance()                // notifications, the last step
        #expect(user?.needsOnboarding == false)
        #expect(auth.onboardingCalls.count == 1)
    }

    @Test func aServerFieldErrorReturnsToItsStep() async {
        let auth = FakeAuth(onboardingError: .fieldValidation(message: "Check the fields.", fields: ["focus_areas": "Pick at least one focus area."]))
        let model = await WizardModel.atGoal(auth: auth)

        _ = await model.advance()

        #expect(model.step == .focusAreas)
        #expect(model.fieldErrors["focus_areas"] == "Pick at least one focus area.")
    }

    @Test func quittingHalfwayResumesWhereItStopped() async {
        let defaults = UserDefaults.ephemeral()
        let first = WizardModel(user: .fixture, auth: FakeAuth(), defaults: defaults)
        _ = await first.advance()
        first.toggle(.learning)
        _ = await first.advance()

        let relaunched = WizardModel(user: .fixture, auth: FakeAuth(), defaults: defaults)
        #expect(relaunched.step == .coachingStyle)
        #expect(relaunched.draft.focusAreas == [.learning])
    }
}

@MainActor
struct GuidedTourTests {
    @Test func runsThreeStepsThenStaysFinished() {
        let defaults = UserDefaults.ephemeral()
        let tour = GuidedTour(defaults: defaults)
        tour.startIfNeeded()
        #expect(tour.current == .today)
        #expect(tour.progressLabel == "1 of 3")

        tour.advance(); tour.advance(); tour.advance()
        #expect(tour.current == nil)

        let nextLaunch = GuidedTour(defaults: defaults)
        nextLaunch.startIfNeeded()
        #expect(nextLaunch.current == nil)
    }

    @Test func skippingEndsItAndSettingsBringsItBack() async {
        let tour = GuidedTour(defaults: .ephemeral())
        tour.startIfNeeded()
        tour.skip()
        #expect(tour.isFinished)

        await tour.restart()
        #expect(tour.current == .today)
    }
}

@MainActor
struct RouterTests {
    @Test(arguments: [
        ("khepri://today", AppDestination.tab(.today)),
        ("khepri://coach", .tab(.coach)),
        ("khepri://settings", .settings),
        ("/app/check-ins", .tab(.more)),
        ("/app/chat/33333333-3333-3333-3333-333333333333", .tab(.coach)),
        ("https://kheprios.com/app/training/abc", .tab(.training)),
        ("khepri://training/plan-1/2", .trainingDay(2)),
        ("khepri://training/plan-1/2/start", .startWorkout(2)),
    ])
    func mapsLinksToDestinations(_ link: String, _ expected: AppDestination) throws {
        #expect(AppRouter.destination(for: try #require(URL(string: link))) == expected)
    }

    @Test func leavesForeignLinksAlone() throws {
        #expect(AppRouter.destination(for: try #require(URL(string: "https://example.com/app/chat"))) == nil)
        #expect(AppRouter.destination(for: try #require(URL(string: "khepri://nowhere"))) == nil)
    }

    @Test func settingsOpensFromTheMoreTab() throws {
        let router = AppRouter()
        router.open(url: try #require(URL(string: "khepri://settings")))
        #expect(router.selectedTab == .more)
        #expect(router.showsSettings)
    }
}

// MARK: - Fakes

final class FakeAuth: AuthServicing, @unchecked Sendable {
    private(set) var onboardingCalls: [OnboardingAnswers] = []
    private let onboardingError: APIError?

    init(onboardingError: APIError? = nil) {
        self.onboardingError = onboardingError
    }

    func completeOnboarding(_ answers: OnboardingAnswers) async throws -> APIUser {
        onboardingCalls.append(answers)
        if let onboardingError { throw onboardingError }
        var user = APIUser.fixture
        user.needsOnboarding = false
        return user
    }

    func currentUser() async throws -> APIUser { .fixture }
    func today() async throws -> TodayResponse { throw APIError.invalidResponse }
    func login(email: String, password: String) async throws -> AuthSession { throw APIError.invalidResponse }
    func signup(email: String, password: String, passwordConfirmation: String, displayName: String) async throws -> AuthSession { throw APIError.invalidResponse }
    func forgotPassword(email: String) async throws {}
    func signInWithGoogle() async throws -> AuthSession { throw APIError.invalidResponse }
    func signInWithApple() async throws -> AuthSession { throw APIError.invalidResponse }
    func signInWithPasskey() async throws -> AuthSession { throw APIError.invalidResponse }
    func registerPasskey(email: String, displayName: String) async throws -> AuthSession { throw APIError.invalidResponse }
    func logout() async {}
}

extension APIUser {
    static let fixture = APIUser(
        id: "22222222-2222-2222-2222-222222222222",
        email: "ana@example.com",
        displayName: "Ana",
        timezone: "Europe/Lisbon",
        needsOnboarding: true
    )
}

extension UserDefaults {
    /// A throwaway suite, so tests never see each other's saved state.
    static func ephemeral() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

extension WizardModel {
    /// A wizard with valid answers, standing on the goal step.
    static func atGoal(auth: FakeAuth) async -> WizardModel {
        let model = WizardModel(user: .fixture, auth: auth, defaults: .ephemeral())
        _ = await model.advance()
        model.toggle(.fitness)
        _ = await model.advance()
        model.choose(.direct)
        _ = await model.advance()
        model.setGoal("Run a half marathon")
        return model
    }
}
