import XCTest

/// Reports and memories against a local server with a seeded report and a
/// proposed memory (scripts/seed-growth-uitest.sh → TEST_RUNNER_GROWTH_*).
final class GrowthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReadRateReportAndReviewMemories() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["GROWTH_EMAIL"], let password = env["GROWTH_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-growth-uitest.sh and pass TEST_RUNNER_GROWTH_EMAIL/PASSWORD")
        }
        let token = try Server.logIn(email: email, password: password)
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Reports"])
        tap(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Week of 14 September'")).firstMatch)
        XCTAssertTrue(app.staticTexts["The week"].waitForExistence(timeout: 15), "the report's heading did not render")
        XCTAssertTrue(app.staticTexts["Two long runs"].exists)
        tap(app.buttons["Useful"])
        let rated = expectation(for: NSPredicate { _, _ in
            let reports = (try? Server.get("/api/v1/reports", token: token)["reports"] as? [[String: Any]]) ?? []
            return reports.first?["helpful"] as? Bool == true
        }, evaluatedWith: nil)
        wait(for: [rated], timeout: 20)
        attach(app, "01-report")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["Memories"])
        XCTAssertTrue(app.staticTexts["Left knee aches on long downhill runs."].waitForExistence(timeout: 15))
        attach(app, "02-memories")
        tap(app.buttons["Keep"])

        tap(app.navigationBars.buttons["Add Memory"])
        type(app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["What should your coach know?"], "Trains before work, around 07:00.")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Trains before work, around 07:00."].waitForExistence(timeout: 15))
        attach(app, "03-remembered")

        let memories = try Server.get("/api/v1/memories", token: token)
        let approved = (memories["approved"] as? [[String: Any]] ?? []).compactMap { $0["content"] as? String }
        // Onboarding writes a couple of its own (focus area, coaching style).
        XCTAssertTrue(Set(approved).isSuperset(of: ["Left knee aches on long downhill runs.", "Trains before work, around 07:00."]))
        XCTAssertEqual((memories["pending"] as? [Any])?.count, 0)
    }
}
