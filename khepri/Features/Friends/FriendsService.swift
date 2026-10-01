import Foundation
import NorthAPI

typealias SocialOverview = Components.Schemas.SocialOverview
typealias Connection = Components.Schemas.ConnectionView
typealias PublicPerson = Components.Schemas.PersonView
typealias FeedItem = Components.Schemas.FeedItem
typealias Sharing = Components.Schemas.Sharing

protocol FriendsServicing: Sendable {
    func overview() async throws -> SocialOverview
    func setHandle(_ handle: String) async throws -> String
    func follow(handle: String) async throws
    func unfollow(_ userID: String) async throws
    func accept(_ userID: String) async throws
    func removeFollower(_ userID: String) async throws
    func block(_ userID: String) async throws
    func unblock(_ userID: String) async throws
    /// Connects this account to whoever's link it was. False when it was
    /// already invited, or the link leads nowhere; neither is an error.
    func redeem(_ code: String) async throws -> Bool
    /// Yours and what friends share with you, newest first.
    func feed() async throws -> [FeedItem]
    func sharing() async throws -> Sharing
    func setSharing(_ sharing: Sharing) async throws -> Sharing
    func giveKudos(_ achievementID: String) async throws
    func takeKudos(_ achievementID: String) async throws
}

struct FriendsService: FriendsServicing {
    var api: Client = API.shared

    func overview() async throws -> SocialOverview {
        try await NorthAPI.call { try await api.getSocial().ok.body.json }
    }

    func setHandle(_ handle: String) async throws -> String {
        try await NorthAPI.call { try await api.setHandle(body: .json(.init(handle: handle))).ok.body.json.handle }
    }

    func follow(handle: String) async throws {
        try await NorthAPI.call { _ = try await api.follow(body: .json(.init(handle: handle))).ok }
    }

    func unfollow(_ userID: String) async throws {
        try await NorthAPI.call { _ = try await api.unfollow(path: .init(userID: userID)).noContent }
    }

    func accept(_ userID: String) async throws {
        try await NorthAPI.call { _ = try await api.acceptFollower(path: .init(userID: userID)).noContent }
    }

    func removeFollower(_ userID: String) async throws {
        try await NorthAPI.call { _ = try await api.removeFollower(path: .init(userID: userID)).noContent }
    }

    func block(_ userID: String) async throws {
        try await NorthAPI.call { _ = try await api.block(path: .init(userID: userID)).noContent }
    }

    func unblock(_ userID: String) async throws {
        try await NorthAPI.call { _ = try await api.unblock(path: .init(userID: userID)).noContent }
    }

    func redeem(_ code: String) async throws -> Bool {
        try await NorthAPI.call { try await api.redeemInvite(path: .init(code: code)).ok.body.json.redeemed }
    }

    func feed() async throws -> [FeedItem] {
        try await NorthAPI.call { try await api.getFeed().ok.body.json.items }
    }

    func sharing() async throws -> Sharing {
        try await NorthAPI.call { try await api.getSharing().ok.body.json }
    }

    func setSharing(_ sharing: Sharing) async throws -> Sharing {
        try await NorthAPI.call { try await api.setSharing(body: .json(sharing)).ok.body.json }
    }

    func giveKudos(_ achievementID: String) async throws {
        try await NorthAPI.call { _ = try await api.giveKudos(path: .init(achievementID: achievementID)).noContent }
    }

    func takeKudos(_ achievementID: String) async throws {
        try await NorthAPI.call { _ = try await api.takeKudos(path: .init(achievementID: achievementID)).noContent }
    }
}

/// An invite link opened before anybody could redeem it: tapped while signed
/// out, or before the app had a session. Kept until sign-in, then redeemed
/// once.
enum PendingInvite {
    private static let key = "invite.pending"

    static func store(_ code: String) {
        UserDefaults.standard.set(code, forKey: key)
    }

    static func take() -> String? {
        guard let code = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return code
    }

    /// Redeems a stored code, if there is one. Failures put it back for the
    /// next try rather than losing somebody's invite to a dropped connection.
    @discardableResult
    static func redeemIfAny(using service: FriendsServicing = FriendsService()) async -> Bool {
        guard let code = take() else { return false }
        do {
            return try await service.redeem(code)
        } catch {
            store(code)
            return false
        }
    }
}
