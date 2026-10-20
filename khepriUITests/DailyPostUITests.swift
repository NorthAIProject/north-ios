import XCTest

/// The daily post against a local server: read it, give kudos, and ask the
/// coach about it. Nothing in the API writes a post, so seed today's first:
///
///     docker exec -i north-client-postgres-1 psql -U north -d <db> -c \
///       "INSERT INTO daily_posts (post_date, theme, title, body)
///        VALUES ((now() at time zone 'utc')::date, 'hydration', 'A glass of water before each meal', '…')"
final class DailyPostUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReadGiveKudosAndAskTheCoach() throws {
        let email = "daily+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Sleep better",
        ])
        guard let today = try Server.get("/api/v1/daily-posts", token: token)["today"] as? [String: Any],
              let title = today["title"] as? String else {
            throw XCTSkip("no daily post today on the local server; seed one (see the comment above)")
        }
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Daily Post"])
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15), "today's post did not show")
        XCTAssertTrue(app.staticTexts["AI-written"].exists || app.otherElements["Written by AI"].exists
            || app.staticTexts["Written by AI"].exists, "the AI badge is missing")
        attach(app, "01-daily-post")

        tap(app.buttons["Give kudos"].firstMatch)
        XCTAssertTrue(app.buttons["Take back kudos"].firstMatch.waitForExistence(timeout: 10))
        let after = try Server.get("/api/v1/daily-posts", token: token)["today"] as? [String: Any]
        XCTAssertEqual(after?["kudoed"] as? Bool, true, "the server did not record kudos")

        tap(app.buttons["daily-post-ask-coach"])
        let composer = app.textFields["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "no conversation opened")
        let drafted = NSPredicate(format: "value BEGINSWITH %@", "About today's post")
        expectation(for: drafted, evaluatedWith: composer)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["Helpful"].exists, "the draft was sent by itself")
        attach(app, "02-ask-coach")
    }
}
