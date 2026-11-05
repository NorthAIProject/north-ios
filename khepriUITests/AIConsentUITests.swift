import XCTest

/// The AI data sharing question against a local server (needs `AI_CONSENT_REQUIRED=true`
/// and at least one provider key set, so the recipients list is not empty).
final class AIConsentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDecliningTurnsAIOffAndSettingsTurnsItBackOn() throws {
        let email = "consent+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Sleep better",
        ])
        var answer = try Server.get("/api/v1/ai-consent", token: token)
        XCTAssertEqual(answer["status"] as? String, "unset")

        let app = launchSignedIn(email: email, password: password, arguments: ["-uitest-ai-consent"])

        let decline = app.buttons["ai-consent-decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 20), "the question was not asked after sign-in")
        XCTAssertTrue(app.staticTexts["Share your data with AI?"].exists)
        XCTAssertTrue(app.buttons["ai-consent-allow"].exists)
        attach(app, "01-question")
        app.swipeUp()
        attach(app, "02-question-scrolled")

        tap(decline)
        XCTAssertTrue(decline.waitForNonExistence(timeout: 15), "the question stayed after answering")
        answer = try Server.get("/api/v1/ai-consent", token: token)
        XCTAssertEqual(answer["status"] as? String, "declined", "the server did not record the answer")

        openTab(app, "Coach")
        let review = app.buttons["ai-off-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), "the Coach tab did not say AI is off")
        XCTAssertTrue(app.staticTexts["AI is off"].exists)
        attach(app, "03-coach-off")

        tap(review)
        let toggle = app.switches["ai-consent-toggle"]
        for _ in 0..<4 where !toggle.isHittable {
            app.swipeUp()
        }
        attach(app, "04-settings")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()

        let allowed = NSPredicate { _, _ in
            (try? Server.get("/api/v1/ai-consent", token: token)["status"] as? String) == "granted"
        }
        expectation(for: allowed, evaluatedWith: NSObject())
        waitForExpectations(timeout: 15)
    }
}
