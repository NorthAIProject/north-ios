import Foundation
import OSLog
import Security

public enum SecureStoreError: LocalizedError, Equatable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .readFailed(let status):
            return "Failed to read from Keychain (OSStatus: \(status))."
        case .writeFailed(let status):
            return "Failed to write to Keychain (OSStatus: \(status))."
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (OSStatus: \(status))."
        case .invalidEncoding:
            return "Data in Keychain could not be encoded as a UTF-8 string."
        }
    }

    /// The Keychain refused to hand an item over because the phone has not
    /// been unlocked since it restarted. The item is still there.
    public var isLocked: Bool {
        self == .readFailed(errSecInteractionNotAllowed)
    }
}

public protocol SecureStringStoring: Sendable {
    func string(for key: String) throws -> String?
    func setString(_ value: String, for key: String) throws
    func removeValue(for key: String) throws
}

/// Generic passwords for this app, readable once the phone has been unlocked
/// after a restart, so the session survives the lock screen: HealthKit
/// deliveries, App Intents and requests finishing in the background run
/// while the phone is locked.
public final class KeychainStringStore: SecureStringStoring, @unchecked Sendable {
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "keychain")

    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.fernandocorreia.khepri") {
        self.service = service
    }

    public func string(for key: String) throws -> String? {
        var query = itemQuery(for: key)
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.readFailed(status) }
        guard let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.invalidEncoding
        }
        if item[kSecAttrAccessible as String] as? String != Self.accessibility as String {
            relaxAccessibility(for: key)
        }
        return value
    }

    public func setString(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = itemQuery(for: key)

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: Self.accessibility
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecureStoreError.writeFailed(updateStatus) }

        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecureStoreError.writeFailed(addStatus) }
    }

    public func removeValue(for key: String) throws {
        let status = SecItemDelete(itemQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.deleteFailed(status)
        }
    }

    private func itemQuery(for key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
    }

    /// Items written by builds before the session had to survive the lock
    /// screen were readable only while unlocked. Reading one proves the phone
    /// is unlocked now, which is when it can be moved over. A failure leaves
    /// it as it was, to try again on the next read.
    private func relaxAccessibility(for key: String) {
        let status = SecItemUpdate(
            itemQuery(for: key) as CFDictionary,
            [kSecAttrAccessible: Self.accessibility] as CFDictionary
        )
        if status != errSecSuccess {
            Self.log.error("Could not move a Keychain item to after-first-unlock: \(status)")
        }
    }
}
