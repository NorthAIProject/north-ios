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

/// The digests one match request carries. The server takes at most
/// `ContactMatching.chunkSize` of both kinds together.
nonisolated struct ContactHashes: Equatable, Sendable {
    var emails: [String] = []
    /// Of E.164 numbers, plus included: see `PhoneNumbers`.
    var phones: [String] = []

    var count: Int { emails.count + phones.count }
}

/// Contact emails and phone numbers as the server matches them: normalised
/// and SHA-256 hashed here, so only the hex digests ever leave the phone.
nonisolated enum ContactMatching {
    /// The most hashes, emails and phones together, the server takes in one
    /// request.
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

    /// Requests of at most `size` digests each: emails first, then phones,
    /// with one request holding both where they meet.
    static func chunks(_ hashes: ContactHashes, size: Int = chunkSize) -> [ContactHashes] {
        let tagged = hashes.emails.map { (isEmail: true, hash: $0) } + hashes.phones.map { (isEmail: false, hash: $0) }
        return stride(from: 0, to: tagged.count, by: size).map { start in
            let slice = tagged[start..<min(start + size, tagged.count)]
            return ContactHashes(emails: slice.filter(\.isEmail).map(\.hash), phones: slice.filter { !$0.isEmail }.map(\.hash))
        }
    }

    /// Asks about every hash, a chunk at a time, and lists each person once
    /// however many of their addresses and numbers you have, by name.
    static func matchAll(_ hashes: ContactHashes, using match: (ContactHashes) async throws -> [ContactMatch]) async throws -> [ContactMatch] {
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

/// The phone's address book, read only to hash the email addresses and
/// phone numbers in it. Nothing read here is kept, logged or sent as it is.
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

    /// The hashed email addresses and phone numbers of every contact Khepri
    /// may see: all of them, or only the ones chosen under limited access.
    /// Numbers saved without "+" or "00" are read as `home`'s. Read off the
    /// main actor, since a large address book takes a moment; only the email
    /// and phone keys are fetched, because the names shown come from Khepri,
    /// not from here.
    @concurrent nonisolated static func hashes(home: CallingCode?) async throws -> ContactHashes {
        let keys = [CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var emails: [String] = []
        var numbers: [String] = []
        try CNContactStore().enumerateContacts(with: request) { contact, stop in
            if Task.isCancelled { stop.pointee = true }
            emails += contact.emailAddresses.map { $0.value as String }
            numbers += contact.phoneNumbers.map { $0.value.stringValue }
        }
        try Task.checkCancellation()
        return ContactHashes(emails: ContactMatching.hashes(of: emails), phones: PhoneNumbers.hashes(of: numbers, home: home))
    }
}
