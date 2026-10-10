import Foundation
import Security
import Testing
@testable import khepri

/// The session must stay readable while the phone is locked: HealthKit
/// deliveries and App Intents run then, and a token they cannot read used to
/// go out missing, earn a 401 and sign the person out.
struct KeychainStringStoreTests {
    private let service = "khepri.tests.\(UUID().uuidString)"

    @Test func storesItemsReadableAfterFirstUnlock() throws {
        let store = KeychainStringStore(service: service)
        defer { try? store.removeValue(for: "token") }

        try store.setString("fresh", for: "token")

        #expect(try store.string(for: "token") == "fresh")
        #expect(accessibility(of: "token") == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    /// Sessions stored by earlier builds were readable only while unlocked.
    /// The first read (the phone is unlocked, or it would have failed) moves
    /// them over, keeping the value.
    @Test func anOlderItemMovesToAfterFirstUnlockWhenRead() throws {
        let store = KeychainStringStore(service: service)
        defer { try? store.removeValue(for: "token") }
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "token",
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecValueData: Data("old".utf8),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        try #require(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
        #expect(accessibility(of: "token") == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)

        #expect(try store.string(for: "token") == "old")

        #expect(accessibility(of: "token") == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(try store.string(for: "token") == "old")
    }

    @Test func aMissingItemIsNilNotAnError() throws {
        #expect(try KeychainStringStore(service: service).string(for: "nothing") == nil)
    }

    private func accessibility(of account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessible as String] as? String
    }
}

/// A Keychain that refuses every read, as it does before the first unlock.
final class LockedStore: SecureStringStoring, @unchecked Sendable {
    private(set) var removed: [String] = []
    func string(for key: String) throws -> String? { throw SecureStoreError.readFailed(errSecInteractionNotAllowed) }
    func setString(_ value: String, for key: String) throws {}
    func removeValue(for key: String) throws { removed.append(key) }
}

struct LockedSessionTests {
    /// Not being able to read the token is not being signed out: the error
    /// reaches the caller, and nothing is deleted.
    @Test func anUnreadableTokenThrowsAndKeepsTheSession() async {
        let store = LockedStore()
        let sessions = AuthSessionManager(secureStore: store)

        await #expect(throws: SecureStoreError.readFailed(errSecInteractionNotAllowed)) {
            try await sessions.validAccessToken()
        }
        #expect(store.removed.isEmpty)
    }
}
