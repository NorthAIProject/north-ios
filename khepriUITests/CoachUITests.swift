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
        // Khepri's mark heads the tab, saying it is ready.
        let ready = NSPredicate(format: "identifier == 'coach-header' AND label CONTAINS 'Ready'")
        XCTAssertTrue(app.descendants(matching: .any).matching(ready).firstMatch.waitForExistence(timeout: 15), "no ready coach header")
        // Onboarding opened a first thread; start a fresh one for the test.
        tap(app.buttons["new-conversation"])

        type(app.textFields["composer"], "How do I do a push-up?")
        tap(app.buttons["Send"])

        XCTAssertTrue(app.buttons["Helpful"].waitForExistence(timeout: 60), "no finished reply")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'fake coach'")).firstMatch.exists)
        attach(app, "01-reply")

        tap(app.buttons["Helpful"])
        XCTAssertTrue(app.buttons["Helpful"].isSelected)
    }

    /// A tap on Today's orb goes to the Coach tab. A hold listens, letting go
    /// sends what was heard, the reply lands in the overlay, a typed follow-up
    /// joins it, and "Open in chat" continues that same thread.
    @MainActor
    func testQuickCoachFromToday() throws {
        let email = "quick+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])

        let app = launchSignedIn(email: email, password: password)
        openTab(app, "Today")
        let orb = app.buttons["coach-orb"]
        XCTAssertTrue(orb.waitForExistence(timeout: 20), "no orb on Today")
        attach(app, "05-orb")

        // Real touches at its centre: the orb's gesture is what is under test.
        let orbCentre = orb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        orbCentre.tap()
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 20), "a tap did not open Coach")
        openTab(app, "Today")

        orbCentre.press(forDuration: 2)
        let phrase = NSPredicate(format: "label == %@", "How many rest days should I take")
        XCTAssertTrue(app.staticTexts.matching(phrase).firstMatch.waitForExistence(timeout: 20), "the heard words were not sent")
        XCTAssertTrue(app.buttons["Helpful"].waitForExistence(timeout: 60), "no finished reply in the overlay")
        attach(app, "06-quick-reply")

        type(app.textFields["composer"], "And what should I eat?")
        tap(app.buttons["Send"])
        let followUp = NSPredicate(format: "label == %@", "And what should I eat?")
        XCTAssertTrue(app.staticTexts.matching(followUp).firstMatch.waitForExistence(timeout: 20), "the follow-up was not sent")
        let replies = app.buttons.matching(identifier: "Helpful")
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: replies)
        waitForExpectations(timeout: 60)
        attach(app, "07-quick-follow-up")

        tap(app.buttons["quick-coach-open-chat"])
        XCTAssertTrue(app.buttons["thread-new-conversation"].waitForExistence(timeout: 20), "Open in chat did not open the thread")
        XCTAssertTrue(app.staticTexts.matching(phrase).firstMatch.waitForExistence(timeout: 20), "a different thread opened")
        attach(app, "08-quick-in-chat")
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

        let composer = app.textFields["composer"]
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
    static func post(_ path: String, token: String?, body: [String: Any], method: String = "POST") throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
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
