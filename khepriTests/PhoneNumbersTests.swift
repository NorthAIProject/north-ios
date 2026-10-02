import Foundation
import Testing
@testable import khepri

struct PhoneNumbersTests {
    /// `printf '+351912345678' | shasum -a 256`, what the server stores for a
    /// verified Portuguese mobile.
    let portugueseMobile = "00839c79aea2116c94def9e14c0493fa0801add3ffb50434478082030ab88e11"

    @Test(arguments: [
        // Portugal: no trunk prefix.
        ("912 345 678", "PT", "+351912345678"),
        ("+351 912 345 678", nil, "+351912345678"),
        ("00351 912345678", nil, "+351912345678"),
        ("21 123 4567", "PT", "+351211234567"),
        // Brazil: trunk 0 before the area code.
        ("(11) 98765-4321", "BR", "+5511987654321"),
        ("011 98765-4321", "BR", "+5511987654321"),
        ("+55 11 98765-4321", "US", "+5511987654321"),
        // United Kingdom: trunk 0, and the "(0)" some write after +44.
        ("07911 123456", "GB", "+447911123456"),
        ("+44 (0)7911 123456", nil, "+447911123456"),
        ("0044 7911 123456", "DE", "+447911123456"),
        // United States: no trunk 0, but often a saved long-distance 1.
        ("(415) 555-0100", "US", "+14155550100"),
        ("1-415-555-0100", "US", "+14155550100"),
        ("+1 415 555 0100", "PT", "+14155550100"),
        // Spain: no trunk prefix.
        ("612 34 56 78", "ES", "+34612345678"),
        ("+34 612345678", nil, "+34612345678"),
        // Germany: trunk 0.
        ("0151 23456789", "DE", "+4915123456789"),
        ("+49 151 23456789", nil, "+4915123456789"),
        ("0049 151 23456789", "GB", "+4915123456789"),
        // Italy keeps its 0: it is part of the number.
        ("06 1234 5678", "IT", "+390612345678"),
    ] as [(String, String?, String)])
    func readsLocalAndInternationalForms(_ raw: String, _ region: String?, _ e164: String) {
        #expect(PhoneNumbers.e164(raw, home: PhoneNumbers.callingCode(region: region)) == e164)
    }

    @Test(arguments: [
        ("912 345 678", nil),           // national, and no country to read it in
        ("112", "PT"),                  // too short
        ("+1234567890123456", nil),     // too long
        ("", "PT"),
        ("call me", "PT"),
        ("+0 123 456 789", nil),        // no calling code starts with 0
    ] as [(String, String?)])
    func skipsWhatCannotBeANumber(_ raw: String, _ region: String?) {
        #expect(PhoneNumbers.e164(raw, home: PhoneNumbers.callingCode(region: region)) == nil)
    }

    @Test func callingCodeOfAVerifiedNumber() {
        #expect(PhoneNumbers.callingCode(of: "+351912345678")?.digits == "351")
        #expect(PhoneNumbers.callingCode(of: "+14155550100")?.digits == "1")
        #expect(PhoneNumbers.callingCode(of: "+447911123456")?.dropsTrunkZero == true)
        #expect(PhoneNumbers.callingCode(of: "+999123456789") == nil)
        #expect(PhoneNumbers.callingCode(of: "") == nil)
    }

    @Test func callingCodeOfARegion() {
        #expect(PhoneNumbers.callingCode(region: "pt")?.digits == "351")
        #expect(PhoneNumbers.callingCode(region: "US")?.dropsTrunkZero == false)
        #expect(PhoneNumbers.callingCode(region: "ZZ") == nil)
        #expect(PhoneNumbers.callingCode(region: nil) == nil)
    }

    @Test func hashesAreOfE164WithThePlusOncePerNumber() {
        let pt = PhoneNumbers.callingCode(region: "PT")
        let hashes = PhoneNumbers.hashes(of: ["912 345 678", "+351912345678", "00351 912 345 678", "112", "+44 7911 123456"], home: pt)
        #expect(hashes.count == 2)
        #expect(hashes.first == portugueseMobile)
        #expect(hashes.allSatisfy { $0.count == 64 && $0 == $0.lowercased() })
    }
}

struct FacebookConnectResultTests {
    @Test(arguments: [("connected", FacebookConnectResult.connected), ("cancelled", .cancelled),
                      ("expired", .expired), ("taken", .taken), ("failed", .failed), ("nonsense", .failed)])
    func readsTheServersVerdict(_ result: String, _ expected: FacebookConnectResult) throws {
        let url = try #require(URL(string: "khepri://friends/facebook?result=\(result)"))
        #expect(FacebookConnectResult(callback: url) == expected)
    }

    @Test func onlyConnectedIsSilent() {
        #expect(FacebookConnectResult.connected.message == nil)
        #expect(FacebookConnectResult.taken.message?.contains("another Khepri account") == true)
    }
}
