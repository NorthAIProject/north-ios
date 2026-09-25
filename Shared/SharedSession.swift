import Foundation
import Security

/// The sign-in session, where the app's widgets can read it.
///
/// The app keeps its session in its own Keychain items. Widgets run in a
/// separate process with a separate default Keychain group, so the app also
/// mirrors the token into a group both targets hold (`keychain-access-groups`,
/// named by `KhepriKeychainGroup` in each Info.plist). The token is the only
/// thing mirrored; widgets fetch everything else from the server with it.
enum SharedSession {
    private static let service = "khepri.shared-session"
    private static let account = "token"

    private static var accessGroup: String? {
        let group = Bundle.main.object(forInfoDictionaryKey: "KhepriKeychainGroup") as? String
        return group?.isEmpty == false ? group : nil
    }

    private static func query() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }

    static func token() -> String? {
        var read = query()
        read[kSecReturnData] = true
        read[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores the token. Readable after the first unlock, so a widget can
    /// refresh while the phone is locked.
    static func store(_ token: String) {
        let attributes: [CFString: Any] = [
            kSecValueData: Data(token.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query() as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            let insert = query().merging(attributes) { $1 }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(query() as CFDictionary)
    }
}
