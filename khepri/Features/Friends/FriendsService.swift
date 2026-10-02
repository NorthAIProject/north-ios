import Foundation
import NorthAPI

typealias SocialOverview = Components.Schemas.SocialOverview
typealias Connection = Components.Schemas.ConnectionView
typealias PublicPerson = Components.Schemas.PersonView
typealias FeedItem = Components.Schemas.FeedItem
typealias Sharing = Components.Schemas.Sharing
typealias PhoneStatus = Components.Schemas.PhoneView
typealias FacebookFriends = Components.Schemas.FacebookFriends

protocol FriendsServicing: Sendable {
    func overview() async throws -> SocialOverview
    func setHandle(_ handle: String) async throws -> String
    /// Asks to follow; the connection says whether it waits for their yes.
    @discardableResult func follow(handle: String) async throws -> Connection
    func unfollow(_ userID: String) async throws
    func accept(_ userID: String) async throws
    func removeFollower(_ userID: String) async throws
    func block(_ userID: String) async throws
    func unblock(_ userID: String) async throws
    /// People already on Khepri among SHA-256 hex digests of contact emails
    /// and phone numbers, at most `ContactMatching.chunkSize` of them.
    func matchContacts(_ hashes: ContactHashes) async throws -> [ContactMatch]
    /// Your verified number, and the one a code is waiting for, if any.
    func phone() async throws -> PhoneStatus
    /// Texts a code. `countryCode` is the calling code a national number is
    /// read in, digits only; nil when the number starts with "+" or "00".
    func startPhoneVerification(_ phone: String, countryCode: String?) async throws -> PhoneStatus
    func checkPhoneCode(_ code: String) async throws -> PhoneStatus
    func cancelPhoneVerification() async throws
    func removePhone() async throws
    func facebook() async throws -> FacebookFriends
    /// Facebook's consent page, for a web authentication session.
    func facebookAuthorizeURL() async throws -> URL
    func disconnectFacebook() async throws
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

    @discardableResult func follow(handle: String) async throws -> Connection {
        try await NorthAPI.call { try await api.follow(body: .json(.init(handle: handle))).ok.body.json }
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

    func matchContacts(_ hashes: ContactHashes) async throws -> [ContactMatch] {
        try await NorthAPI.call {
            try await api.matchContacts(body: .json(.init(hashes: hashes.emails, phoneHashes: hashes.phones))).ok.body.json.people
                .map { ContactMatch(person: $0.value1, following: $0.value2.following) }
        }
    }

    func phone() async throws -> PhoneStatus {
        try await NorthAPI.call { try await api.getPhone().ok.body.json }
    }

    func startPhoneVerification(_ phone: String, countryCode: String?) async throws -> PhoneStatus {
        try await NorthAPI.call {
            try await api.startPhoneVerification(body: .json(.init(phone: phone, countryCode: countryCode))).ok.body.json
        }
    }

    func checkPhoneCode(_ code: String) async throws -> PhoneStatus {
        try await NorthAPI.call { try await api.checkPhoneCode(body: .json(.init(code: code))).ok.body.json }
    }

    func cancelPhoneVerification() async throws {
        try await NorthAPI.call { _ = try await api.cancelPhoneVerification().noContent }
    }

    func removePhone() async throws {
        try await NorthAPI.call { _ = try await api.removePhone().noContent }
    }

    func facebook() async throws -> FacebookFriends {
        try await NorthAPI.call { try await api.getFacebookFriends().ok.body.json }
    }

    func facebookAuthorizeURL() async throws -> URL {
        let raw = try await NorthAPI.call { try await api.connectFacebook().ok.body.json.authorizeUrl }
        guard let url = URL(string: raw) else { throw APIError.invalidResponse }
        return url
    }

    func disconnectFacebook() async throws {
        try await NorthAPI.call { _ = try await api.disconnectFacebook().noContent }
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
