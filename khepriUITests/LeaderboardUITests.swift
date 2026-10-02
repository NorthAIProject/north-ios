import XCTest

/// The leaderboard against a local server: the account follows friends who
/// share their XP, and does not share its own yet. Turning sharing on from
/// the board takes the "friends don't see you" line away.
///
/// Pass TEST_RUNNER_LEADERBOARD_EMAIL and TEST_RUNNER_LEADERBOARD_PASSWORD
/// (an account with XP sharing off and at least one friend on the board).
final class LeaderboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTheBoardRanksFriendsAndSharingPutsYouOnIt() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["LEADERBOARD_EMAIL"], let password = env["LEADERBOARD_PASSWORD"] else {
            throw XCTSkip("seed accounts and pass TEST_RUNNER_LEADERBOARD_EMAIL/PASSWORD")
        }
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Friends"])
        tap(app.buttons["Leaderboard"])
        XCTAssertTrue(app.navigationBars["Leaderboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["XP this week"].waitForExistence(timeout: 15))
        attach(app, "01-level")
        // The board sits under the level card; a List builds rows only on screen.
        let hidden = app.staticTexts["Your friends don't see you on this board."]
        for _ in 0..<4 where !hidden.exists { app.swipeUp() }
        XCTAssertTrue(hidden.waitForExistence(timeout: 10), "the board does not say you are hidden")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '(you)'")).firstMatch.exists, "you are not on the board")
        attach(app, "02-xp-week")

        tap(app.buttons["Share Your XP and Level"])
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: hidden)
        wait(for: [gone], timeout: 15)

        tap(app.buttons["Streak"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label ENDSWITH ' days' OR label ENDSWITH ' day'")).firstMatch.waitForExistence(timeout: 10),
                      "the streak board shows no days")
        attach(app, "03-streak")
    }
}
