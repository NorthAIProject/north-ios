import Foundation

public enum JWTTokenInspector {
    public struct Payload: Equatable, Sendable {
        public let userID: String?
        public let expiresAt: Date?

        public init(userID: String?, expiresAt: Date?) {
            self.userID = userID
            self.expiresAt = expiresAt
        }
    }

    public static func payload(from token: String) -> Payload? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              let data = Data(base64URLEncoded: String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let userId = (json["userId"] as? String) ?? (json["sub"] as? String)
        let exp = json["exp"] as? Double
        let expiresAt = exp.map(Date.init(timeIntervalSince1970:))
        return Payload(userID: userId, expiresAt: expiresAt)
    }

    public static func expirationDate(in token: String) -> Date? {
        payload(from: token)?.expiresAt
    }

    public static func userID(in token: String) -> String? {
        payload(from: token)?.userID
    }
}
