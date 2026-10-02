import XCTest

/// The inbox, decision revisits and the areas scoreboard against a local
/// server, checked on the server where it matters.
final class GrowthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInboxDecisionAndAreas() throws {
        let email = "growth+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        try Server.post("/api/v1/decisions", token: token, body: ["title": "Run the half in March"])
        let app = launchSignedIn(email: email, password: password)

        // Inbox: save a thought, then file it in the journal.
        openTab(app, "More")
        tap(app.buttons["Inbox"])
        type(app.textFields["A thought, a link, something that happened…"], "Felt calm after the long run")
        tap(app.buttons["Save to Inbox"])
        let row = app.staticTexts["Felt calm after the long run"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the item was not saved")
        attach(app, "01-inbox")
        row.press(forDuration: 1.2)
        tap(app.buttons["Journal"])
        XCTAssertTrue(app.staticTexts["Nothing waiting."].waitForExistence(timeout: 10), "the item was not filed")
        XCTAssertEqual(try Server.get("/api/v1/inbox", token: token)["open"] as? Int, 0)

        // Decision: looked back on, partly held.
        app.navigationBars.buttons.firstMatch.tap()
        let decisions = app.buttons["Decisions"]
        for _ in 0..<4 where !decisions.isHittable { app.swipeUp() }
        tap(decisions)
        tap(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Run the half in March'")).firstMatch)
        tap(app.buttons["Partly"])
        attach(app, "02-held")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["1 looked back on: 0 held, 1 partly, 0 didn't"].waitForExistence(timeout: 10),
                      "the calibration line did not appear")
        let calibration = try Server.get("/api/v1/decisions/calibration", token: token)
        XCTAssertEqual(calibration["partly"] as? Int, 1)

        // Areas by week.
        openTab(app, "Progress")
        let byWeek = app.buttons["By Week"]
        for _ in 0..<4 where !byWeek.isHittable { app.swipeUp() }
        tap(byWeek)
        XCTAssertTrue(app.navigationBars["Areas by Week"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Body"].waitForExistence(timeout: 20), "no areas")
        attach(app, "03-areas")
    }
}
