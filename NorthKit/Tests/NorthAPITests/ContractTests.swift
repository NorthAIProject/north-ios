import Foundation
import OpenAPIRuntime
import Testing
@testable import NorthAPI

/// The web app pins every /api/v1 response shape in a golden file; these
/// tests decode each one with the types generated from openapi.yaml. A golden
/// file that fails here means the server and the spec disagree, which is the
/// bug a generated client would otherwise find in production.
struct ContractTests {
    typealias Schemas = Components.Schemas

    @Test func authResponse() throws {
        let response = try decode(Schemas.AuthResponse.self, "auth")
        #expect(response.token == "opaque-session-token")
        #expect(response.user.needsOnboarding)
    }

    @Test func me() throws {
        let response = try decode(Schemas.MeResponse.self, "me")
        #expect(response.user.email == "ana@example.com")
    }

    @Test func onboarding() throws {
        let response = try decode(Schemas.OnboardingResponse.self, "onboarding")
        #expect(response.threadId != nil)
    }

    @Test func today() throws {
        let response = try decode(Schemas.TodayResponse.self, "today")
        #expect(response.snapshot.goals.first?.progress == 40)
        #expect(response.snapshot.sleep.quality == 4)
        #expect(response.snapshot.nudges.count == 1)
    }

    @Test func passkeyCeremony() throws {
        let response = try decode(Schemas.PasskeyCeremonyResponse.self, "passkey-ceremony")
        #expect(response.challengeId == "66666666-6666-6666-6666-666666666666")
    }

    @Test func captureParse() throws {
        let response = try decode(Schemas.ParseResponse.self, "parse")
        #expect(response.items.count == 3)
    }

    @Test func captureCommit() throws {
        let response = try decode(Schemas.CommitResponse.self, "commit")
        #expect(response.written == 1)
    }

    @Test func conversation() throws {
        let detail = try decode(Schemas.ConversationDetail.self, "conversation")
        // The tool plumbing turn is left out on the server: question, answer.
        #expect(detail.messages.map(\.role) == [.user, .coach])
        #expect(detail.messages.last?.exercises == ["push-up"])
        #expect(detail.pendingApproval?.calls.first?.name == "log_check_in")
    }

    @Test func conversations() throws {
        let list = try decode(Schemas.ConversationList.self, "conversations")
        #expect(list.conversations.map(\.kind) == [.chat, .reflection])
        #expect(list.conversations.last?.ended == true)
    }

    @Test func exercise() throws {
        let exercise = try decode(Schemas.ExerciseDetail.self, "exercise")
        #expect(exercise.art?.frames.count == 3)
        #expect(exercise.art?.size == 512)
        #expect(exercise.art?.credit.contains("CC BY-SA") == true)
    }

    /// Every golden file the sync script copied has a test above.
    @Test func everyGoldenFileIsDecoded() throws {
        let covered: Set = ["auth", "me", "onboarding", "today", "passkey-ceremony", "parse", "commit",
                            "conversation", "conversations", "exercise"]
        let names = try FileManager.default.contentsOfDirectory(at: contractDirectory, includingPropertiesForKeys: nil)
            .map { $0.lastPathComponent.replacingOccurrences(of: ".golden.json", with: "") }
        #expect(Set(names) == covered, "add a decode test for each new golden file")
    }

    private var contractDirectory: URL {
        Bundle.module.resourceURL!.appending(path: "Contract")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let data = try Data(contentsOf: contractDirectory.appending(path: "\(name).golden.json"))
        let decoder = JSONDecoder()
        let transcoder = NorthAPI.configuration.dateTranscoder
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            return try transcoder.decode(raw)
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct DateTranscoderTests {
    let transcoder = FlexibleISO8601DateTranscoder()

    @Test(arguments: [
        "2026-09-24T07:15:00Z",
        "2026-09-24T07:15:00.5Z",
        "2026-09-24T07:15:00.123Z",
        "2026-09-24T07:15:00.123456789Z",
        "2026-09-24T08:15:00.123456789+01:00",
    ])
    func readsWhatGoWrites(_ raw: String) throws {
        let date = try transcoder.decode(raw)
        let expected = try transcoder.decode("2026-09-24T07:15:00Z")
        #expect(abs(date.timeIntervalSince(expected)) < 1)
    }

    @Test func roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        #expect(try transcoder.decode(transcoder.encode(date)) == date)
    }
}
