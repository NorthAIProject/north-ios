import Foundation

/// A country's calling code, and whether its national numbers are written
/// with a trunk "0" that E.164 leaves out ("07911 123456" in the UK is
/// +447911123456).
nonisolated struct CallingCode: Equatable, Hashable, Sendable {
    /// Without the plus: "351".
    let digits: String
    let dropsTrunkZero: Bool
}

/// Phone numbers as the server matches them: E.164, "+" and 8 to 15 digits.
/// Written here rather than with a phone-number library because contact
/// matching needs only the shape, not validation: a number that reads wrong
/// simply matches nobody.
nonisolated enum PhoneNumbers {
    /// The regions people most often have contacts in, by ISO code. A
    /// convenience for numbers saved without their "+": any number saved
    /// with "+" or "00" works wherever it is from. Italy keeps its leading 0;
    /// Portugal, Spain and the rest marked false have no trunk prefix at all.
    static let callingCodes: [String: CallingCode] = [
        "PT": .init(digits: "351", dropsTrunkZero: false),
        "BR": .init(digits: "55", dropsTrunkZero: true),
        "ES": .init(digits: "34", dropsTrunkZero: false),
        "GB": .init(digits: "44", dropsTrunkZero: true),
        "US": .init(digits: "1", dropsTrunkZero: false),
        "CA": .init(digits: "1", dropsTrunkZero: false),
        "FR": .init(digits: "33", dropsTrunkZero: true),
        "DE": .init(digits: "49", dropsTrunkZero: true),
        "IT": .init(digits: "39", dropsTrunkZero: false),
        "NL": .init(digits: "31", dropsTrunkZero: true),
        "BE": .init(digits: "32", dropsTrunkZero: true),
        "IE": .init(digits: "353", dropsTrunkZero: true),
        "CH": .init(digits: "41", dropsTrunkZero: true),
        "AT": .init(digits: "43", dropsTrunkZero: true),
        "LU": .init(digits: "352", dropsTrunkZero: false),
        "DK": .init(digits: "45", dropsTrunkZero: false),
        "SE": .init(digits: "46", dropsTrunkZero: true),
        "NO": .init(digits: "47", dropsTrunkZero: false),
        "FI": .init(digits: "358", dropsTrunkZero: true),
        "PL": .init(digits: "48", dropsTrunkZero: false),
        "CZ": .init(digits: "420", dropsTrunkZero: false),
        "GR": .init(digits: "30", dropsTrunkZero: false),
        "RO": .init(digits: "40", dropsTrunkZero: true),
        "UA": .init(digits: "380", dropsTrunkZero: true),
        "TR": .init(digits: "90", dropsTrunkZero: true),
        "IL": .init(digits: "972", dropsTrunkZero: true),
        "AE": .init(digits: "971", dropsTrunkZero: true),
        "ZA": .init(digits: "27", dropsTrunkZero: true),
        "AO": .init(digits: "244", dropsTrunkZero: false),
        "MZ": .init(digits: "258", dropsTrunkZero: false),
        "CV": .init(digits: "238", dropsTrunkZero: false),
        "MX": .init(digits: "52", dropsTrunkZero: false),
        "AR": .init(digits: "54", dropsTrunkZero: true),
        "CL": .init(digits: "56", dropsTrunkZero: false),
        "AU": .init(digits: "61", dropsTrunkZero: true),
        "NZ": .init(digits: "64", dropsTrunkZero: true),
        "IN": .init(digits: "91", dropsTrunkZero: true),
        "JP": .init(digits: "81", dropsTrunkZero: true),
        "KR": .init(digits: "82", dropsTrunkZero: true),
        "CN": .init(digits: "86", dropsTrunkZero: true),
        "SG": .init(digits: "65", dropsTrunkZero: false),
        "HK": .init(digits: "852", dropsTrunkZero: false),
    ]

    /// The calling code for an ISO region such as `Locale.current.region`.
    static func callingCode(region: String?) -> CallingCode? {
        region.flatMap { callingCodes[$0.uppercased()] }
    }

    /// The calling code an E.164 number starts with, when it is one of ours.
    /// Calling codes are prefix-free, so the longest match is the only one.
    static func callingCode(of e164: String) -> CallingCode? {
        guard e164.hasPrefix("+") else { return nil }
        let digits = e164.dropFirst()
        return Set(callingCodes.values)
            .filter { digits.hasPrefix($0.digits) }
            .max { $0.digits.count < $1.digits.count }
    }

    /// `raw` as E.164 ("+351912345678"), or nil when it cannot be one.
    ///
    /// Saved with "+" or "00", a number says its own country. Without either
    /// it is national and is read in `home`: one trunk "0" dropped where the
    /// country uses one, then its calling code put in front. With no `home`,
    /// a national number is skipped rather than guessed.
    static func e164(_ raw: String, home: CallingCode?) -> String? {
        // "+44 (0)20 7946 0958": the bracketed 0 is a hint for dialling at home.
        let text = raw.replacingOccurrences(of: "(0)", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(text.filter { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty else { return nil }

        var international: String
        if text.hasPrefix("+") {
            international = digits
        } else if digits.hasPrefix("00") {
            international = String(digits.dropFirst(2))
        } else {
            guard let home else { return nil }
            var national = Substring(digits)
            if home.dropsTrunkZero, national.hasPrefix("0") { national = national.dropFirst() }
            // North Americans often save the long-distance 1: "1 415 555 0100".
            if home.digits == "1", national.count == 11, national.hasPrefix("1") { national = national.dropFirst() }
            international = home.digits + national
        }
        guard (8...15).contains(international.count), !international.hasPrefix("0") else { return nil }
        return "+" + international
    }

    /// One digest per distinct number, in the order first seen, of the E.164
    /// form including the plus. What cannot be read is left out.
    static func hashes(of numbers: [String], home: CallingCode?) -> [String] {
        var seen = Set<String>()
        return numbers.compactMap { e164($0, home: home) }.filter { seen.insert($0).inserted }.map(ContactMatching.hash)
    }
}
