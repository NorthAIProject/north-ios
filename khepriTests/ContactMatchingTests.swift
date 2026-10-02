import Foundation
import NorthAPI
import Testing
@testable import khepri

struct ContactMatchingTests {
    /// `printf 'ana@example.com' | shasum -a 256`, which is what the server's
    /// encode(sha256(lower(email)), 'hex') gives for the same address.
    let ana = "8e43ca37701228e74983efdbd0cff5c16b3b1e5d4e29a7c05626d4d25a018e11"

    @Test func addressesAreTrimmedAndLowerCased() {
        #expect(ContactMatching.normalize("  Ana@Example.COM\n") == "ana@example.com")
        #expect(ContactMatching.normalize("ana@example.com") == "ana@example.com")
    }

    @Test func whatCannotBeAnAddressIsDropped() {
        #expect(ContactMatching.normalize("") == nil)
        #expect(ContactMatching.normalize("   ") == nil)
        #expect(ContactMatching.normalize("not an address") == nil)
    }

    @Test func hashIsLowerCaseHexSHA256() {
        #expect(ContactMatching.hash("ana@example.com") == ana)
    }

    @Test func spellingsOfOneAddressHashOnce() {
        let hashes = ContactMatching.hashes(of: ["Ana@Example.com", " ana@example.com ", "", "joao@example.com"])
        #expect(hashes.count == 2)
        #expect(hashes.first == ana)
        #expect(hashes.allSatisfy { $0.count == 64 && $0 == $0.lowercased() })
        #expect(!hashes.contains { $0.contains("@") })
    }

    @Test func chunksHoldAtMostTheServersLimit() {
        let emails = (0..<4500).map(String.init)
        let chunks = ContactMatching.chunks(ContactHashes(emails: emails))
        #expect(chunks.map(\.count) == [2000, 2000, 500])
        #expect(chunks.flatMap(\.emails) == emails && chunks.allSatisfy(\.phones.isEmpty))
        #expect(ContactMatching.chunks(ContactHashes()).isEmpty)
        #expect(ContactMatching.chunks(ContactHashes(emails: (0..<2000).map(String.init))).count == 1)
    }

    @Test func emailsAndPhonesShareTheLimit() {
        let emails = (0..<1500).map { "e\($0)" }, phones = (0..<1000).map { "p\($0)" }
        let chunks = ContactMatching.chunks(ContactHashes(emails: emails, phones: phones))
        #expect(chunks.map(\.count) == [2000, 500])
        #expect(chunks[0].emails.count == 1500 && chunks[0].phones.count == 500)
        #expect(chunks[1].emails.isEmpty && chunks[1].phones.count == 500)
        #expect(chunks.flatMap(\.emails) == emails && chunks.flatMap(\.phones) == phones)
        #expect(ContactMatching.chunks(ContactHashes(phones: phones)).map(\.count) == [1000])
    }

    @Test func everyChunkIsAskedAndEachPersonListedOnceByName() async throws {
        let hashes = ContactHashes(emails: (0..<2000).map(String.init), phones: ["p"])
        let zoe = match("1", "Zoë"), ana = match("2", "ana")
        var asked: [ContactHashes] = []
        let people = try await ContactMatching.matchAll(hashes) { chunk in
            asked.append(chunk)
            return asked.count == 1 ? [zoe, ana] : [ana]
        }
        #expect(asked.map(\.count) == [2000, 1] && asked.last?.phones == ["p"])
        #expect(people.map(\.person.displayName) == ["ana", "Zoë"])
    }

    @Test func noContactsAsksNothing() async throws {
        var asked = false
        let people = try await ContactMatching.matchAll(ContactHashes()) { _ in
            asked = true
            return []
        }
        #expect(!asked && people.isEmpty)
    }

    private func match(_ id: String, _ name: String) -> ContactMatch {
        ContactMatch(person: PublicPerson(id: id, displayName: name, handle: name.lowercased()), following: "")
    }
}
