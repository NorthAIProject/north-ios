import XCTest

/// Care, nutrition, the journal, decisions and the bell against a local
/// server, each change checked on the server.
final class LifeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCareNutritionJournalDecisionsAndBell() throws {
        let email = "life+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        let app = launchSignedIn(email: email, password: password)

        // Care: a glass of water and a habit done today.
        openTab(app, "More")
        tap(app.buttons["Care"])
        tap(app.buttons["+250 ml"])
        wait(for: [serverSays(token, "/api/v1/care") { ($0["water"] as? [String: Any])?["totalMl"] as? Int == 250 }], timeout: 20)
        tap(app.buttons["Add a Habit"])
        type(app.textFields["e.g. Stretch 10 minutes"], "Stretch")
        tap(app.navigationBars.buttons["Save"])
        let habit = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Stretch'")).firstMatch
        XCTAssertTrue(habit.waitForExistence(timeout: 15))
        tap(habit)
        wait(for: [serverSays(token, "/api/v1/care") {
            (($0["habits"] as? [[String: Any]])?.first?["doneToday"] as? Bool) == true
        }], timeout: 20)
        attach(app, "01-care")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Nutrition: an ingredient of one's own, then logged.
        tap(app.buttons["Nutrition"])
        tap(app.segmentedControls.buttons["Ingredients"])
        tap(app.navigationBars.buttons["Add Ingredient"])
        type(app.textFields["Name"], "Test oats")
        type(app.textFields["Calories (kcal)"], "380")
        type(app.textFields["Protein (g)"], "13")
        tap(app.navigationBars.buttons["Save"])
        tap(app.segmentedControls.buttons["Today"])
        tap(app.buttons["Log Food"])
        type(app.searchFields.firstMatch, "Test oats")
        tap(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Test oats'")).firstMatch)
        tap(app.buttons["Log It"])
        wait(for: [serverSays(token, "/api/v1/nutrition/log") {
            let totals = $0["totals"] as? [String: Any]
            return (totals?["calories"] as? Double).map { abs($0 - 380) < 1 } ?? false
        }], timeout: 20)
        attach(app, "02-nutrition")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The journal.
        tap(app.buttons["Mind"])
        tap(app.navigationBars.buttons["Write"])
        type(app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["What's on your mind?"], "Hard week, good long run.")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Hard week, good long run."].waitForExistence(timeout: 15))
        attach(app, "03-journal")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // A decision.
        tap(app.buttons["Decisions"])
        tap(app.navigationBars.buttons["New Decision"])
        type(app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["What are you deciding?"], "December or March")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["December or March"].waitForExistence(timeout: 15))
        attach(app, "04-decisions")

        // The bell, on Today.
        openTab(app, "Today")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch)
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10))
        attach(app, "05-bell")
        tap(app.navigationBars.buttons["Done"])
    }

    private func serverSays(_ token: String, _ path: String, _ check: @escaping ([String: Any]) -> Bool) -> XCTestExpectation {
        expectation(for: NSPredicate { _, _ in (try? Server.get(path, token: token)).map(check) ?? false }, evaluatedWith: nil)
    }
}
