import XCTest

/// A progress check against a local server: measurements saved from More →
/// Progress check reach the history, and Today's figure takes its shape from
/// them.
final class ProgressCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAMeasuredCheckShapesTodaysFigure() throws {
        let email = "progress+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"
        ])
        // The shape is read against height.
        try Server.post("/api/v1/calculator/biometrics", token: token, body: [
            "weightKg": 92, "heightCm": 175, "dateOfBirth": "1990-04-02", "sex": "male"
        ], method: "PUT")

        let app = launchSignedIn(email: email, password: password)
        dismissSavePassword(app)
        scrollToFigure(app)
        sleep(3)
        attach(app, "00-today-modelled")
        attachFigure(app, "00-figure-modelled")

        openTab(app, "More")
        tap(app.buttons["Progress check"].firstMatch)
        XCTAssertTrue(app.navigationBars["Progress check"].waitForExistence(timeout: 10))
        attach(app, "01-progress-empty")
        tap(app.buttons["progress-new"])
        XCTAssertTrue(app.navigationBars["New check"].waitForExistence(timeout: 5))
        attach(app, "02-new-check")
        for (field, value) in [("waist", "112"), ("hips", "114"), ("chest", "118")] {
            let input = app.textFields["progress-\(field)"]
            for _ in 0..<6 where !input.isHittable { app.swipeUp() }
            type(input, value)
        }
        attach(app, "03-new-check-filled")
        // A tap while the keyboard is still settling can be lost; one retry.
        let save = app.buttons["progress-save"]
        tap(save)
        if !app.navigationBars["New check"].waitForNonExistence(timeout: 4), save.exists {
            attach(app, "03b-save-retried")
            tap(save)
        }
        let saved = app.descendants(matching: .any)["progress-check"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "the saved check is not in the history")
        attach(app, "04-progress-saved")

        let body = try Server.get("/api/v1/body/current", token: token)
        let waist = (body["morph"] as? [String: Any])?["waist"] as? Double ?? 0
        XCTAssertGreaterThan(waist, 0.5, "the check did not shape the figure")

        openTab(app, "Today")
        scrollToFigure(app)
        sleep(3)
        attach(app, "05-today-shaped")
        attachFigure(app, "05-figure-shaped")
    }

    /// The body card sits below the day's cards; scroll until the whole
    /// figure clears the tab bar.
    @MainActor
    private func scrollToFigure(_ app: XCUIApplication) {
        let figure = app.descendants(matching: .any).matching(identifier: "body-map").firstMatch
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<12 where !(figure.exists && figure.frame.maxY < tabBar.frame.minY) {
            _ = answerSavePassword(app)
            app.swipeUp(velocity: .slow)
            usleep(600_000)
        }
        XCTAssertTrue(figure.exists, "no body figure on Today")
    }

    /// The figure alone, at full resolution.
    @MainActor
    private func attachFigure(_ app: XCUIApplication, _ name: String) {
        let figure = app.descendants(matching: .any).matching(identifier: "body-map").firstMatch
        let shot = XCTAttachment(screenshot: figure.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
