import XCTest

/// The knowledge library against a local server: a note written on the phone
/// is found by the same search the coach uses.
final class KnowledgeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWriteANoteAndFindIt() throws {
        let email = "knowledge+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Knowledge"])
        tap(app.navigationBars.buttons["Add"])
        tap(app.buttons["Write a Note"])
        type(app.textFields["Title"], "Knee rehab")
        type(app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["Write it down"],
             "Wall sits, three sets of forty seconds, before every long run.")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Knee rehab"].waitForExistence(timeout: 15))
        attach(app, "01-library")

        // Indexing runs on the worker; search once the note is ready.
        let ready = expectation(for: NSPredicate { _, _ in
            let docs = (try? Server.get("/api/v1/knowledge", token: token)["documents"] as? [[String: Any]]) ?? []
            return docs.first?["status"] as? String == "ready"
        }, evaluatedWith: nil)
        wait(for: [ready], timeout: 60)

        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        type(search, "wall sits")
        let match = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Wall sits'")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 15), "search did not find the note")
        attach(app, "02-search")
        tap(match)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'before every long run'")).firstMatch.waitForExistence(timeout: 15))
        attach(app, "03-document")
    }
}
