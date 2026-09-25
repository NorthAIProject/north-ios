import XCTest

/// Captures the App Store screenshots from a seeded local account
/// (scripts/seed-screenshots.sh → TEST_RUNNER_SHOTS_*). Runs only when
/// TEST_RUNNER_SHOTS_DIR names a folder on the host; each screen is written
/// there as a PNG, prefixed with the device name.
final class ScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureStoreScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["SHOTS_EMAIL"], let password = env["SHOTS_PASSWORD"], let dir = env["SHOTS_DIR"] else {
            throw XCTSkip("seed with scripts/seed-screenshots.sh and pass TEST_RUNNER_SHOTS_EMAIL/PASSWORD/DIR")
        }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let app = launchSignedIn(email: email, password: password)

        func shoot(_ name: String) throws {
            // Let charts, images and the exercise loop settle.
            sleep(3)
            let url = URL(fileURLWithPath: dir).appending(path: "\(device)-\(name).png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
            attach(app, name)
        }

        go(app, "Today")
        XCTAssertTrue(app.staticTexts["Streak"].waitForExistence(timeout: 20))
        try shoot("today")

        go(app, "Coach")
        tap(app.staticTexts["Knee after the long run"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'left one again'")).firstMatch.waitForExistence(timeout: 20))
        try shoot("coach")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        go(app, "Training")
        XCTAssertTrue(app.staticTexts["Lower body"].firstMatch.waitForExistence(timeout: 20))
        try shoot("training")
        tap(app.staticTexts["Lower body"].firstMatch)
        XCTAssertTrue(app.staticTexts["Goblet Squat"].firstMatch.waitForExistence(timeout: 20))
        try shoot("training-day")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        go(app, "Progress")
        XCTAssertTrue(app.staticTexts["Areas"].firstMatch.waitForExistence(timeout: 30))
        try shoot("progress")

        go(app, "More")
        tap(app.buttons["Goals"])
        XCTAssertTrue(app.staticTexts["Run a 10k under an hour"].waitForExistence(timeout: 20))
        try shoot("goals")
        tap(app.staticTexts["Run a 10k under an hour"])
        sleep(2)
        try shoot("goal-detail")
    }

    /// iPad's iOS 26 tab bar floats at the top and is not exposed as a tab
    /// bar; its tabs are plain buttons there. The phone uses the shared helper.
    @MainActor
    private func go(_ app: XCUIApplication, _ name: String) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return openTab(app, name) }
        let deadline = Date.now.addingTimeInterval(30)
        while Date.now < deadline {
            answerSavePassword(app)
            if let tab = app.buttons.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex.first(where: \.isHittable) {
                tab.tap()
                return
            }
            usleep(500_000)
        }
        XCTFail("no tappable \(name) tab")
    }
}
