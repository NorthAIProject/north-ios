import XCTest

/// Building a meal plan with the coach against a local server, with the
/// account seeded by scripts/seed-training-uitest.sh (which also works out a
/// macro target, so the form opens).
///
/// The fake model answers in prose, never a plan, so a build ends in the
/// "couldn't build" refusal: that is the server having checked three drafts
/// and refused them, which proves the whole round trip. A real model is needed
/// to see a draft on the review screen.
final class MealPlanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBuildWithAIAsksTheServerAndRemembersTheAnswers() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TRAINING_EMAIL"], let password = env["TRAINING_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-training-uitest.sh and pass TEST_RUNNER_TRAINING_EMAIL/PASSWORD")
        }
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        let nutrition = app.buttons["Nutrition"]
        for _ in 0..<6 where !nutrition.isHittable { app.swipeUp() }
        tap(nutrition)
        tap(app.buttons["Plans"])
        tap(app.buttons["meal-plans.build"])

        XCTAssertTrue(app.navigationBars["Build Meal Plan"].waitForExistence(timeout: 15))
        let exclusions = app.textViews["meal-generate.exclusions"].exists
            ? app.textViews["meal-generate.exclusions"] : app.textFields["meal-generate.exclusions"]
        XCTAssertTrue(exclusions.waitForExistence(timeout: 15), "the form did not open; is there a macro target?")
        type(exclusions, "dairy, peanuts")
        attach(app, "01-form")

        let build = app.buttons["meal-generate.build"]
        for _ in 0..<4 where !build.isHittable { app.swipeUp() }
        tap(build)
        let refused = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'couldn'")).firstMatch
        XCTAssertTrue(refused.waitForExistence(timeout: 120), "no answer from the server")
        attach(app, "02-refused")

        // The answers were saved before the model was asked: the form opens
        // with them next time.
        app.buttons["Cancel"].tap()
        tap(app.buttons["meal-plans.build"])
        let again = app.textViews["meal-generate.exclusions"].exists
            ? app.textViews["meal-generate.exclusions"] : app.textFields["meal-generate.exclusions"]
        let remembered = NSPredicate(format: "value CONTAINS 'peanuts'")
        expectation(for: remembered, evaluatedWith: again)
        waitForExpectations(timeout: 15)
        attach(app, "03-remembered")
    }
}
