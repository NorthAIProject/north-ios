import XCTest

/// The coach tab against a local server (Debug's base URL, localhost:8090).
///
/// Run the server with `AI_PROVIDER_CHAIN=fake` so replies are deterministic
/// and free. The fake model never calls tools, so the exercise card test uses
/// an account the host seeds first (scripts/seed-coach-uitest.sh) and passes in
/// through TEST_RUNNER_COACH_EMAIL / TEST_RUNNER_COACH_PASSWORD.
final class CoachUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A message goes out, the reply streams back as events, and the stored
    /// reply can be rated.
    @MainActor
    func testReplyStreamsAndCanBeRated() throws {
        let email = "coach+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])

        let app = launchSignedIn(email: email, password: password)
        openTab(app, "Coach")
        // Onboarding opened a first thread; start a fresh one for the test.
        tap(app.buttons["new-conversation"])

        type(app.textFields["Message your coach"], "How do I do a push-up?")
        tap(app.buttons["Send"])

        XCTAssertTrue(app.buttons["Helpful"].waitForExistence(timeout: 60), "no finished reply")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'fake coach'")).firstMatch.exists)
        attach(app, "01-reply")

        tap(app.buttons["Helpful"])
        XCTAssertTrue(app.buttons["Helpful"].isSelected)
    }

    /// A reply that looked an exercise up carries a native card; the card opens
    /// the full exercise.
    @MainActor
    func testExerciseCardOpensTheExercise() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["COACH_EMAIL"], let password = env["COACH_PASSWORD"] else {
            throw XCTSkip("seed an account with scripts/seed-coach-uitest.sh and pass TEST_RUNNER_COACH_EMAIL/PASSWORD")
        }
        let app = launchSignedIn(email: email, password: password)
        openTab(app, "Coach")
        tap(app.cells.firstMatch)

        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'push'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no exercise card on the seeded reply")
        sleep(2) // let the loop show a pose beyond the first
        attach(app, "02-card")

        card.tap()
        // Headers are uppercase only visually (.textCase); accessibility reads "Works".
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'works'")).firstMatch.waitForExistence(timeout: 15), "exercise sheet did not open")
        attach(app, "03-sheet")
    }

    /// Dictated words land in the composer, not in a message: nothing is sent
    /// until Send. Under test the microphone hears a fixed sentence.
    @MainActor
    func testDictationFillsTheComposer() throws {
        let email = "dictate+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])

        let app = launchSignedIn(email: email, password: password)
        openTab(app, "Coach")
        tap(app.buttons["new-conversation"])

        let composer = app.textFields["Message your coach"]
        let microphone = app.buttons["dictate"]
        tap(microphone)
        expectation(for: NSPredicate(format: "label == 'Stop dictating'"), evaluatedWith: microphone)
        waitForExpectations(timeout: 10)
        tap(microphone)

        let heard = NSPredicate(format: "value == %@", "How many rest days should I take")
        expectation(for: heard, evaluatedWith: composer)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["Helpful"].exists, "dictation sent the message by itself")
        attach(app, "04-dictated")

        tap(app.buttons["Send"])
        XCTAssertTrue(app.buttons["Helpful"].waitForExistence(timeout: 60), "no finished reply")
    }





}

/// Calls the local server directly, for setting up accounts.
enum Server {
    static let base = URL(string: "http://localhost:8090")!

    static func signUp(email: String, password: String) throws -> String {
        let json = try post("/api/v1/auth/signup", token: nil, body: [
            "email": email, "password": password, "passwordConfirmation": password, "displayName": "Ana",
        ])
        guard let token = json["token"] as? String else { throw URLError(.badServerResponse) }
        return token
    }

    static func logIn(email: String, password: String) throws -> String {
        let json = try post("/api/v1/auth/login", token: nil, body: ["email": email, "password": password])
        guard let token = json["token"] as? String else { throw URLError(.badServerResponse) }
        return token
    }

    static func get(_ path: String, token: String) throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let done = DispatchSemaphore(value: 0)
        var body = Data()
        URLSession.shared.dataTask(with: request) { data, _, _ in
            body = data ?? Data()
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        return (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    @discardableResult
    static func post(_ path: String, token: String?, body: [String: Any]) throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let done = DispatchSemaphore(value: 0)
        var result: (Data?, HTTPURLResponse?) = (nil, nil)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            result = (data, response as? HTTPURLResponse)
            done.signal()
        }.resume()
        // Onboarding asks the model to open the first thread, which can take a while.
        _ = done.wait(timeout: .now() + 120)
        guard let status = result.1?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "\(path) answered \(result.1?.statusCode ?? 0); is north-web-app running on :8090?"])
        }
        return (try? JSONSerialization.jsonObject(with: result.0 ?? Data()) as? [String: Any]) ?? [:]
    }
}
