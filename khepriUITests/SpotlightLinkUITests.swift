import XCTest

/// The links a Spotlight result or a Siri phrase opens: one exercise as a
/// sheet, one goal over the Goals list. Spotlight itself cannot be driven
/// from a test, so this opens the same khepri:// links it fires.
///
/// Needs a local server and an account with one goal, passed as
/// TEST_RUNNER_LINK_EMAIL, TEST_RUNNER_LINK_PASSWORD and
/// TEST_RUNNER_LINK_GOAL_ID.
final class SpotlightLinkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExerciseAndGoalLinksOpenTheirScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["LINK_EMAIL"], let password = env["LINK_PASSWORD"], let goalID = env["LINK_GOAL_ID"] else {
            throw XCTSkip("seed an account with one goal and pass TEST_RUNNER_LINK_EMAIL/PASSWORD/GOAL_ID")
        }
        let app = launchSignedIn(email: email, password: password)
        openTab(app, "Today")

        open(app, "khepri://exercises/push-up")
        XCTAssertTrue(app.staticTexts["Push-up"].waitForExistence(timeout: 15), "the exercise sheet did not open")
        attach(app, "01-exercise")
        app.swipeDown(velocity: .fast)

        open(app, "khepri://goals/\(goalID)")
        XCTAssertTrue(app.navigationBars["Run a 10k"].waitForExistence(timeout: 15), "the goal did not open")
        attach(app, "02-goal")
    }

    /// Through the system, as Spotlight does. `XCUIApplication.open` relaunches
    /// the app with the test's arguments, and -uitest-reset signs it out.
    @MainActor
    private func open(_ app: XCUIApplication, _ link: String) {
        XCUIDevice.shared.system.open(URL(string: link)!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
