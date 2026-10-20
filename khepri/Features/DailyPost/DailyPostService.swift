import Foundation
import NorthAPI

typealias DailyPost = Components.Schemas.DailyPost
typealias DailyPosts = Components.Schemas.DailyPosts

protocol DailyPostServicing: Sendable {
    /// Today's post, when there is one, and up to 13 before it.
    func posts() async throws -> DailyPosts
    func giveKudos(_ postID: String) async throws
    func takeKudos(_ postID: String) async throws
}

struct DailyPostService: DailyPostServicing {
    var api: Client = API.shared

    func posts() async throws -> DailyPosts {
        try await NorthAPI.call { try await api.getDailyPosts().ok.body.json }
    }

    func giveKudos(_ postID: String) async throws {
        try await NorthAPI.call { _ = try await api.giveDailyPostKudos(path: .init(postID: postID)).noContent }
    }

    func takeKudos(_ postID: String) async throws {
        try await NorthAPI.call { _ = try await api.takeDailyPostKudos(path: .init(postID: postID)).noContent }
    }
}

extension DailyPost {
    /// The body split on blank lines: the server writes plain text with a
    /// blank line between paragraphs.
    var paragraphs: [String] {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The UTC day as a date at noon, safe from zone shifts at midnight.
    var day: Date {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? .now
    }

    /// What "Ask the coach" puts in the composer. English, like the post.
    var coachDraft: String {
        "About today's post, \"\(title)\": "
    }

    /// The post with kudos given or taken back, for an optimistic update.
    func withKudos(_ given: Bool) -> DailyPost {
        var copy = self
        guard given != kudoed else { return copy }
        copy.kudoed = given
        copy.kudos = max(0, kudos + (given ? 1 : -1))
        return copy
    }
}
