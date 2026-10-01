import XCTest

/// Crews against a local server: Ana's crew has a weekly challenge and Ana
/// checked in today. The seeded joiner opens the crew link from outside the
/// app and lands on the board.
///
/// Pass TEST_RUNNER_CREW_JOINER, TEST_RUNNER_CREW_PASSWORD and
/// TEST_RUNNER_CREW_CODE.
final class CrewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testACrewLinkJoinsAndOpensTheBoard() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["CREW_JOINER"], let password = env["CREW_PASSWORD"], let code = env["CREW_CODE"] else {
            throw XCTSkip("seed a crew and pass TEST_RUNNER_CREW_JOINER/PASSWORD/CODE")
        }
        let app = launchSignedIn(email: email, password: password)
        openTab(app, "Today")

        XCUIDevice.shared.system.open(URL(string: "khepri://i/c/\(code)")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { springboard.buttons["Open"].tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        XCTAssertTrue(app.navigationBars["Morning runners"].waitForExistence(timeout: 20), "the crew did not open")
        XCTAssertTrue(app.staticTexts["5 check-ins each, Monday to Sunday."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1/5"].exists, "Ana's week is not on the board")
        XCTAssertTrue(app.buttons["Invite to the Crew"].exists)
        attach(app, "01-board")
    }
}
