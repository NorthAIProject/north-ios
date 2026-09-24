import Foundation
import NorthAPI

/// The server's activity timer: the same sessions the web's Activity page
/// starts and stops, which is where calories and the coach's view of
/// training come from.
protocol ActivityServicing: Sendable {
    func start(_ activityCode: String) async throws -> ActivitySession
    /// The session open on the account, from any device, if there is one.
    func openSession() async throws -> ActivitySession?
    func pause(_ sessionID: String) async throws -> ActivitySession
    func resume(_ sessionID: String) async throws -> ActivitySession
    func stop(_ sessionID: String) async throws -> ActivitySession
    func cancel(_ sessionID: String) async throws
}

struct ActivityService: ActivityServicing {
    var api: Client = API.shared

    func start(_ activityCode: String) async throws -> ActivitySession {
        try await NorthAPI.call { try await api.startActivity(body: .json(.init(activityCode: activityCode))).created.body.json }
    }

    func openSession() async throws -> ActivitySession? {
        try await NorthAPI.call { try await api.getActivity().ok.body.json.active }
    }

    func pause(_ sessionID: String) async throws -> ActivitySession {
        try await NorthAPI.call { try await api.pauseActivity(path: .init(sessionID: sessionID)).ok.body.json }
    }

    func resume(_ sessionID: String) async throws -> ActivitySession {
        try await NorthAPI.call { try await api.resumeActivity(path: .init(sessionID: sessionID)).ok.body.json }
    }

    func stop(_ sessionID: String) async throws -> ActivitySession {
        try await NorthAPI.call { try await api.stopActivity(path: .init(sessionID: sessionID)).ok.body.json }
    }

    func cancel(_ sessionID: String) async throws {
        try await NorthAPI.call { _ = try await api.cancelActivity(path: .init(sessionID: sessionID)).noContent }
    }
}
