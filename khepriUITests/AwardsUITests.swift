import XCTest

/// The unlock moment against a local server on the fake model: a fresh account
/// finishes its first workout, the cover celebrates the badge once, and after
/// Done and a relaunch it does not come back. Seed with
/// scripts/seed-training-uitest.sh (TEST_RUNNER_TRAINING_*).
///
/// The launch test needs an account that already has a badge waiting on the
/// server, earned while the app was not running (TEST_RUNNER_LAUNCH_EMAIL and
/// _PASSWORD): a new account whose first follower arrived by the API.
final class AwardsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstWorkoutCelebratesOnceAndNotAfterRelaunch() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TRAINING_EMAIL"], let password = env["TRAINING_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-training-uitest.sh and pass TEST_RUNNER_TRAINING_EMAIL/PASSWORD")
        }
        let token = try Server.logIn(email: email, password: password)
        XCTAssertEqual(try unseen(token).count, 0, "the account must start with nothing to celebrate")
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "Training")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Monday'")).firstMatch)
        tap(app.buttons["Start Workout"])
        XCTAssertTrue(app.staticTexts["Goblet Squat"].waitForExistence(timeout: 15))
        // The set sheet needs a weight before it logs.
        tap(app.buttons["Done · Set 1"])
        tap(app.buttons["plus.circle.fill"])
        tap(app.buttons["log-set"])
        XCTAssertTrue(app.staticTexts["REST"].waitForExistence(timeout: 10))
        tap(app.buttons["Skip Rest"])
        XCTAssertTrue(app.buttons["Done · Set 2"].waitForExistence(timeout: 10))
        tap(app.buttons["End"])
        tap(app.buttons["Finish and Save"])
        XCTAssertTrue(app.staticTexts["Saved to your activity. Your coach will see it."].waitForExistence(timeout: 20))
        tap(app.buttons["Done"])

        // The cover opens over the tab the workout closed onto.
        let celebration = app.buttons["awards.done"]
        XCTAssertTrue(celebration.waitForExistence(timeout: 20), "the first workout did not celebrate")
        let page = NSPredicate(format: "label BEGINSWITH 'Award earned, First Workout'")
        XCTAssertTrue(app.staticTexts.matching(page).firstMatch.waitForExistence(timeout: 10))
        attach(app, "01-celebration")
        XCTAssertEqual(try unseen(token).isEmpty, false, "the server marks it seen only after Done")

        tap(celebration)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: celebration)
        wait(for: [gone], timeout: 10)
        let seen = expectation(
            for: NSPredicate { _, _ in (try? self.unseen(token))?.isEmpty == true }, evaluatedWith: nil)
        wait(for: [seen], timeout: 15)

        // Relaunched on the same session: nothing to celebrate again.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-uitest-skip-tour", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        again.launch()
        openTab(again, "Progress")
        XCTAssertTrue(again.buttons["awards.card"].waitForExistence(timeout: 20), "the Awards card is missing")
        attach(again, "02-progress-card")
        XCTAssertFalse(again.buttons["awards.done"].exists)
    }

    /// A badge earned while the app was closed is celebrated when it opens:
    /// the cover comes up once and stays up, on a fresh sign-in and again on a
    /// relaunch that never pressed Done.
    @MainActor
    func testBadgeEarnedWhileClosedCelebratesOnLaunchAndStays() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["LAUNCH_EMAIL"], let password = env["LAUNCH_PASSWORD"] else {
            throw XCTSkip("seed an account with an unseen badge and pass TEST_RUNNER_LAUNCH_EMAIL/PASSWORD")
        }
        let token = try Server.logIn(email: email, password: password)
        XCTAssertEqual(try unseen(token).count, 1, "the account must have one badge waiting")

        let app = launchSignedIn(email: email, password: password)
        assertCoverComesUpAndStays(app, name: "03-launch-signed-in")

        // Killed with the cover up: the badge was never marked, so it is due again.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-uitest-skip-tour", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        again.launch()
        let done = assertCoverComesUpAndStays(again, name: "04-launch-relaunched")
        XCTAssertEqual(try unseen(token).count, 1, "nothing is marked until Done")

        tap(done)
        let seen = expectation(
            for: NSPredicate { _, _ in (try? self.unseen(token))?.isEmpty == true }, evaluatedWith: nil)
        wait(for: [seen], timeout: 15)
    }

    /// The cover appears, and is still the same one, up and hittable, a few
    /// seconds later: not flashed away by a second request for it.
    @MainActor
    @discardableResult
    private func assertCoverComesUpAndStays(_ app: XCUIApplication, name: String) -> XCUIElement {
        let done = app.buttons["awards.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "the waiting badge did not celebrate on launch")
        let page = NSPredicate(format: "label BEGINSWITH 'Award earned, First Follower'")
        XCTAssertTrue(app.staticTexts.matching(page).firstMatch.waitForExistence(timeout: 10))
        // Settled: the cover is still sliding up when the button first exists.
        let settled = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: done)
        wait(for: [settled], timeout: 10)
        let deadline = Date.now.addingTimeInterval(4)
        while Date.now < deadline {
            XCTAssertTrue(done.exists && done.isHittable, "the cover went away on its own")
            usleep(250_000)
        }
        attach(app, name)
        return done
    }

    private func unseen(_ token: String) throws -> [[String: Any]] {
        try Server.get("/api/v1/awards/unseen", token: token)["awards"] as? [[String: Any]] ?? []
    }
}
