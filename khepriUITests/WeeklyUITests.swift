import XCTest

/// The weekly review against a local server: priorities, goal order and a
/// deload week, checked on the server.
final class WeeklyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWeeklyReviewSavesTheFocus() throws {
        let email = "weekly+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        try Server.post("/api/v1/goals", token: token, body: ["title": "Run a half marathon", "category": "fitness"])
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Plan the Week"])
        XCTAssertTrue(app.navigationBars["The Week"].waitForExistence(timeout: 15), "the review did not open")
        attach(app, "01-week")

        tap(app.buttons["Next"])
        type(app.textFields["Priority 1"], "Three runs")
        attach(app, "02-priorities")

        tap(app.buttons["Next"])
        XCTAssertTrue(app.staticTexts["Run a half marathon"].waitForExistence(timeout: 5))
        attach(app, "03-goals")

        tap(app.buttons["Next"])
        tap(app.buttons["Deload"])
        tap(app.buttons["Save the Week"])
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 15), "the week was not saved")
        attach(app, "04-saved")

        let review = try Server.get("/api/v1/weekly/review", token: token)
        let current = review["current"] as? [String: Any]
        XCTAssertEqual(current?["volume"] as? String, "deload")
        XCTAssertEqual(current?["priorities"] as? [String], ["Three runs"])
    }
}
