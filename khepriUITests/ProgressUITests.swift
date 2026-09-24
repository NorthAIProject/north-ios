import XCTest

/// Progress and the fitness connections, against a local server with a seeded
/// account that has synced steps (scripts/seed-training-uitest.sh).
final class ProgressUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProgressShowsSyncedStepsAndConnections() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TRAINING_EMAIL"], let password = env["TRAINING_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-training-uitest.sh and pass TEST_RUNNER_TRAINING_EMAIL/PASSWORD")
        }
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "Progress")
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 15))
        let steps = app.buttons["Steps"]
        for _ in 0..<6 where !steps.isHittable { app.swipeUp() }
        attach(app, "01-progress")

        // The steps the seed synced, charted on the detail page.
        tap(steps)
        XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Nothing from Apple Health for this window. Connect it in Settings → Connections, and allow this kind of data."]
            .waitForExistence(timeout: 3), "the synced steps did not reach the chart")
        attach(app, "02-steps")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The two connections, from Settings.
        openTab(app, "More")
        tap(app.buttons["Settings"])
        tap(app.buttons["Apple Health"])
        XCTAssertTrue(app.switches["Sync Apple Health"].waitForExistence(timeout: 10))
        attach(app, "03-health")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app.buttons["Strava"])
        let unavailable = app.staticTexts["Strava is not set up on this server."]
        let connect = app.buttons["Connect Strava"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10) || connect.exists, "Strava settings showed neither state")
        attach(app, "04-strava")
    }
}
