import Contacts
import CryptoKit
import Foundation
import NorthAPI

/// Somebody in your contacts who is already on Khepri.
nonisolated struct ContactMatch: Identifiable, Equatable, Sendable {
    let person: PublicPerson
    /// "", pending or accepted: how you follow them already.
    var following: String

    var id: String { person.id }
}

/// Contact emails as the server matches them: trimmed, lower-cased and
/// SHA-256 hashed here, so only the hex digests ever leave the phone.
nonisolated enum ContactMatching {
    /// The most hashes the server takes in one request.
    static let chunkSize = 2000

    /// What the server hashes: the address trimmed and lower-cased. Nil for
    /// anything that cannot be an address, which could never match.
    static func normalize(_ email: String) -> String? {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean.contains("@") ? clean : nil
    }

    /// The lower-case hex SHA-256 of an already normalised address.
    static func hash(_ normalized: String) -> String {
        SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// One digest per distinct address, in the order first seen.
    static func hashes(of emails: [String]) -> [String] {
        var seen = Set<String>()
        return emails.compactMap(normalize).filter { seen.insert($0).inserted }.map(hash)
    }

    static func chunks(_ hashes: [String], size: Int = chunkSize) -> [[String]] {
        stride(from: 0, to: hashes.count, by: size).map { Array(hashes[$0..<min($0 + size, hashes.count)]) }
    }

    /// Asks about every hash, a chunk at a time, and lists each person once
    /// however many of their addresses you have, by name.
    static func matchAll(_ hashes: [String], using match: ([String]) async throws -> [ContactMatch]) async throws -> [ContactMatch] {
        var people: [String: ContactMatch] = [:]
        for chunk in chunks(hashes) {
            for person in try await match(chunk) { people[person.id] = person }
        }
        return people.values.sorted {
            $0.person.displayName.localizedStandardCompare($1.person.displayName) == .orderedAscending
        }
    }
}

/// Where Contacts access stands, in the terms the screen acts on.
enum ContactsAccess {
    case undecided, allowed, limited, refused, restricted
}

/// The phone's address book, read only to hash the email addresses in it.
/// Nothing read here is kept, logged or sent as it is.
enum ContactBook {
    static var access: ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .undecided
        case .authorized: .allowed
        case .limited: .limited
        case .restricted: .restricted
        case .denied: .refused
        @unknown default: .refused
        }
    }

    /// Shows the system prompt the first time; afterwards answers at once.
    static func requestAccess() async -> Bool {
        (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    /// The hashed email addresses of every contact Khepri may see: all of
    /// them, or only the ones chosen under limited access. Read off the main
    /// actor, since a large address book takes a moment; only the email key
    /// is fetched, because the names shown come from Khepri, not from here.
    @concurrent nonisolated static func emailHashes() async throws -> [String] {
        let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
        var emails: [String] = []
        try CNContactStore().enumerateContacts(with: request) { contact, stop in
            if Task.isCancelled { stop.pointee = true }
            emails += contact.emailAddresses.map { $0.value as String }
        }
        try Task.checkCancellation()
        return ContactMatching.hashes(of: emails)
    }
}
