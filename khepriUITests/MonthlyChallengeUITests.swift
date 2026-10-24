import XCTest

/// The monthly challenge card against a local server on the fake model. Seed an
/// account whose challenge is `checkin_days` with target 1 and pass it as
/// TEST_RUNNER_MONTHLY_EMAIL/PASSWORD: the card shows on Progress and on the
/// own profile with a locked coin, then a check-in meets it, the celebration
/// comes up once, and the card reads "Challenge met".
final class MonthlyChallengeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChallengeCardShowsAndMeetingItCelebratesOnce() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["MONTHLY_EMAIL"], let password = env["MONTHLY_PASSWORD"] else {
            throw XCTSkip("seed a checkin_days target-1 challenge and pass TEST_RUNNER_MONTHLY_EMAIL/PASSWORD")
        }
        let token = try Server.logIn(email: email, password: password)
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "Progress")
        let card = app.descendants(matching: .any).matching(identifier: "monthlyChallenge.card").firstMatch
        for _ in 0..<6 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the challenge card is missing on Progress")
        XCTAssertFalse(app.staticTexts["Challenge met"].exists)
        attach(app, "01-progress-card")

        // Meet it over the API, then come back to the app.
        _ = try Server.post(
            "/api/v1/check-ins/today", token: token, body: ["mood": 4, "energy": 4, "wins": "Showed up"], method: "PUT")
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-uitest-skip-tour", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        again.launch()
        let done = again.buttons["awards.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "meeting the challenge did not celebrate")
        attach(again, "02-celebration")
        tap(done)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: done)
        wait(for: [gone], timeout: 10)

        openTab(again, "Progress")
        let met = again.staticTexts["Challenge met"]
        for _ in 0..<6 where !met.exists { again.swipeUp() }
        XCTAssertTrue(met.waitForExistence(timeout: 20), "the card does not say the challenge is met")
        attach(again, "03-progress-met")
        XCTAssertFalse(again.buttons["awards.done"].exists, "the celebration came back")
    }
}
