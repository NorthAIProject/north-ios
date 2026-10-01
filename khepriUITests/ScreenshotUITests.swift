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
        // US English for the en-US store listing, and demo Apple Health data
        // because the simulator's Health store is empty.
        let app = launchSignedIn(email: email, password: password,
                                 arguments: ["-uitest-demo-health", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        func shoot(_ name: String) throws {
            // Let charts, images and the exercise loop settle, and clear the
            // save-password sheet, which can land late over the first screen.
            dismissSavePassword(app, within: 3)
            sleep(1)
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
        // The thread hides the navigation bar; the header has its own Back.
        tap(app.buttons["Back"])

        go(app, "Training")
        XCTAssertTrue(app.staticTexts["Lower body"].firstMatch.waitForExistence(timeout: 20))
        try shoot("training")
        tap(labelled(app.buttons, "Lower body"))
        XCTAssertTrue(labelled(app.staticTexts, "Goblet Squat").waitForExistence(timeout: 20))
        try shoot("training-day")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        go(app, "Progress")
        XCTAssertTrue(app.staticTexts["Areas"].firstMatch.waitForExistence(timeout: 30))
        try shoot("progress")

        go(app, "More")
        tap(app.buttons["Goals"])
        let tenK = labelled(app.buttons, "Run a 10k under an hour")
        XCTAssertTrue(tenK.waitForExistence(timeout: 20))
        try shoot("goals")
        tap(tenK)
        sleep(2)
        try shoot("goal-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app.buttons["Friends"])
        XCTAssertTrue(labelled(app.descendants(matching: .any), "7 days of check-ins in a row").waitForExistence(timeout: 20))
        try shoot("friends")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app.buttons["Crews"])
        tap(labelled(app.buttons, env["SHOTS_CREW"] ?? "Morning runners"))
        XCTAssertTrue(app.buttons["Invite to the Crew"].waitForExistence(timeout: 20))
        try shoot("crew")
    }

    /// Rows read their title and details as one label, so match on part of it.
    private func labelled(_ query: XCUIElementQuery, _ text: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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
