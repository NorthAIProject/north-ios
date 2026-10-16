import XCTest

/// The "your week" card and the recap sheet against a local server: a few
/// lifting days over the week, the 7/30 day switch, and a post to friends that first
/// asks to share training.
final class RecapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecapOpensSwitchesAndPostsToFriends() throws {
        let email = "recap+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Run more",
        ])
        let iso = ISO8601DateFormatter()
        for daysAgo in [1, 3, 5] {
            let performed = iso.string(from: Date.now.addingTimeInterval(-Double(daysAgo) * 24 * 3600))
            for set in 1...3 {
                try Server.post("/api/v1/lifts/sets", token: token, body: [
                    "exerciseName": "Box squat", "exerciseSlug": "barbell-back-squat-to-box",
                    "setNumber": set, "weightKg": 100, "reps": 5, "performedAt": performed,
                ])
            }
        }
        let app = launchSignedIn(email: email, password: password)

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Your week'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the your-week card did not show")
        dismissSavePassword(app)
        attach(app, "01-today-card")
        tap(card)

        XCTAssertTrue(app.navigationBars["Last 7 days"].waitForExistence(timeout: 15), "the recap did not open")
        XCTAssertTrue(app.staticTexts["Active days"].waitForExistence(timeout: 10))
        attach(app, "02-week")

        tap(app.buttons["30 days"])
        XCTAssertTrue(app.navigationBars["Last 30 days"].waitForExistence(timeout: 10))
        attach(app, "03-month")

        tap(app.buttons["Share recap"])
        tap(app.buttons["Post to friends"])
        let shareTraining = app.buttons["Share training and post"]
        XCTAssertTrue(shareTraining.waitForExistence(timeout: 10), "a hidden post did not offer to share training")
        attach(app, "04-share-training")
        tap(shareTraining)
        XCTAssertTrue(app.staticTexts["Posted to your friends feed."].waitForExistence(timeout: 10))
        attach(app, "05-posted")

        let feed = try Server.get("/api/v1/feed", token: token)
        let items = feed["items"] as? [[String: Any]] ?? []
        XCTAssertEqual(items.first?["kind"] as? String, "recap_shared")
        let sharing = try Server.get("/api/v1/social/sharing", token: token)
        XCTAssertEqual(sharing["training"] as? Bool, true)

        tap(app.buttons["Share recap"])
        tap(app.buttons["Share…"])
        // The system share sheet, with the rendered card as its preview.
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10)
            || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 5), "the share sheet did not open")
        attach(app, "06-share-sheet")
    }
}
