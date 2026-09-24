import XCTest

/// Goals and check-ins against a local server, checked on the server.
final class GoalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoalMilestoneNoteAndCheckIn() throws {
        let email = "goals+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Goals"])

        // Onboarding's near-term goal may already be one; create another either way.
        tap(app.navigationBars.buttons["New Goal"])
        type(app.textFields["What do you want to achieve?"], "Run a half marathon")
        tap(app.navigationBars.buttons["Save"])
        let goalRow = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Run a half marathon'")).firstMatch
        XCTAssertTrue(goalRow.waitForExistence(timeout: 15))
        attach(app, "01-goals")

        tap(goalRow)
        type(app.textFields["Add a milestone"], "Run 10 km")
        tap(app.buttons["Add"])
        let milestone = app.buttons["Run 10 km"]
        XCTAssertTrue(milestone.waitForExistence(timeout: 10))
        tap(milestone)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Run 10 km' AND value == 'Done'")).firstMatch.waitForExistence(timeout: 10))

        tap(app.buttons["Add a Note"])
        type(app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["What happened?"], "Ran 12 km, felt easy.")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Ran 12 km, felt easy."].waitForExistence(timeout: 10))
        attach(app, "02-goal")

        let saved = expectation(for: NSPredicate { _, _ in
            let goals = (try? Server.get("/api/v1/goals", token: token)["goals"] as? [[String: Any]]) ?? []
            guard let goal = goals.first(where: { $0["title"] as? String == "Run a half marathon" }) else { return false }
            let latest = goal["latestUpdate"] as? [String: Any]
            return goal["milestoneDone"] as? Int == 1 && latest?["note"] as? String == "Ran 12 km, felt easy."
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 20)

        // Today's check-in.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["Check-ins"])
        let mood4 = app.segmentedControls.firstMatch.buttons["4"]
        tap(mood4)
        type(app.textFields["A win, however small"], "Long run done")
        // Below the keyboard after typing; scroll to it as a person would.
        let checkIn = app.buttons["Check In"]
        for _ in 0..<5 where !checkIn.isHittable { app.swipeUp() }
        tap(checkIn)
        XCTAssertTrue(app.buttons["Edit Today's Check-in"].waitForExistence(timeout: 15))
        attach(app, "03-check-in")

        let checkIns = try Server.get("/api/v1/check-ins", token: token)
        let today = checkIns["today"] as? [String: Any]
        XCTAssertEqual(today?["mood"] as? Int, 4)
        XCTAssertEqual(today?["wins"] as? String, "Long run done")
        XCTAssertEqual(checkIns["streak"] as? Int, 1)
    }
}
