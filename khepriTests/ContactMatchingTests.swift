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
        let hashes = (0..<4500).map(String.init)
        let chunks = ContactMatching.chunks(hashes)
        #expect(chunks.map(\.count) == [2000, 2000, 500])
        #expect(chunks.flatMap { $0 } == hashes)
        #expect(ContactMatching.chunks([]).isEmpty)
        #expect(ContactMatching.chunks((0..<2000).map(String.init)).count == 1)
    }

    @Test func everyChunkIsAskedAndEachPersonListedOnceByName() async throws {
        let hashes = (0..<2001).map(String.init)
        let zoe = match("1", "Zoë"), ana = match("2", "ana")
        var asked: [Int] = []
        let people = try await ContactMatching.matchAll(hashes) { chunk in
            asked.append(chunk.count)
            return asked.count == 1 ? [zoe, ana] : [ana]
        }
        #expect(asked == [2000, 1])
        #expect(people.map(\.person.displayName) == ["ana", "Zoë"])
    }

    @Test func noContactsAsksNothing() async throws {
        var asked = false
        let people = try await ContactMatching.matchAll([]) { _ in
            asked = true
            return []
        }
        #expect(!asked && people.isEmpty)
    }

    private func match(_ id: String, _ name: String) -> ContactMatch {
        ContactMatch(person: PublicPerson(id: id, displayName: name, handle: name.lowercased()), following: "")
    }
}
