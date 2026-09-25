import XCTest

/// Phase 8a against a local server, with the account seeded by
/// scripts/seed-training-uitest.sh: the insights pages, logging an activity
/// after the fact, and diets saved to the server.
final class ParityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInsightsPagesActivityLogAndDiets() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TRAINING_EMAIL"], let password = env["TRAINING_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-training-uitest.sh and pass TEST_RUNNER_TRAINING_EMAIL/PASSWORD")
        }
        let app = launchSignedIn(email: email, password: password)

        // A score row opens its domain page.
        openTab(app, "Progress")
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 15))
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Body'")).firstMatch)
        XCTAssertTrue(app.navigationBars["Body"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Hours Slept"].waitForExistence(timeout: 15), "the body page did not load")
        attach(app, "01-body")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The timeline, under More, shows the goal the seed created.
        let timeline = app.buttons["Timeline"]
        for _ in 0..<6 where !timeline.isHittable { app.swipeUp() }
        tap(timeline)
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Goal"].waitForExistence(timeout: 15), "the timeline has no entries")
        attach(app, "02-timeline")

        // Log an activity after the fact; it lands in the history.
        openTab(app, "Training")
        tap(app.buttons["Training Options"])
        tap(app.buttons["Activity History"])
        XCTAssertTrue(app.navigationBars["Activity History"].waitForExistence(timeout: 15))
        tap(app.buttons["Log Activity"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activity'")).firstMatch)
        tap(app.buttons["Hiking"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Hiking"].waitForExistence(timeout: 15), "the logged activity is not in the history")
        attach(app, "03-activity-history")

        // A diet switched on is still on after leaving and coming back, so it
        // reached the server.
        openTab(app, "More")
        tap(app.buttons["Settings"])
        let diets = app.buttons["Diets"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
        for _ in 0..<6 where !diets.isHittable { app.swipeUp() }
        tap(diets)
        let glutenFree = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Gluten-free'")).firstMatch
        XCTAssertTrue(glutenFree.waitForExistence(timeout: 15))
        XCTAssertEqual(glutenFree.value as? String, "0")
        glutenFree.switches.firstMatch.tap()
        let on = NSPredicate(format: "value == '1'")
        expectation(for: on, evaluatedWith: glutenFree)
        waitForExpectations(timeout: 10)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(diets)
        XCTAssertTrue(glutenFree.waitForExistence(timeout: 15))
        expectation(for: on, evaluatedWith: glutenFree)
        waitForExpectations(timeout: 10)
        attach(app, "04-diets")
    }
}
