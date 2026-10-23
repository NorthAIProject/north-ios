import Foundation
import NorthKit
import SwiftUI
import Testing

/// The coin medals are drawn from the json the web app ships; these hold the
/// bundled copy to what both sides rely on.
struct MedalsTests {
    private let areas = ["training", "lifts", "consistency", "habits", "nutrition", "hydration", "sleep", "mind", "goals", "body", "social"]

    @Test func theBundledFileDecodes() {
        let medals = Medals.shared
        #expect(medals.areas.count == areas.count)
        #expect(medals.hasGlyph(for: "workouts_1"))
        #expect(medals.hasGlyph(for: "pr_1"))
    }

    @Test func everyAreaHasColours() {
        for area in areas {
            let style = Medals.shared.style(forArea: area)
            #expect(Medals.shared.areas[area] != nil, "\(area) has no colours")
            #expect(style.fillHex.hasPrefix("#") && style.rimHex.hasPrefix("#"), "\(area): \(style)")
        }
        #expect(Medals.shared.monthlyRimHex.hasPrefix("#"))
    }

    @Test func anUnknownAreaFallsBackToSlate() {
        let slate = Medals.shared.style(forArea: "body")
        #expect(Medals.shared.style(forArea: "telepathy") == slate)
        #expect(slate.fillHex == "#475569")
    }

    @Test func aBadgeWithoutAGlyphStillDraws() {
        #expect(!Medals.shared.hasGlyph(for: "badge_from_the_future"))
    }

    @Test func aMalformedColourIsRejected() {
        let json = #"""
            {"coin": {"viewBox": 100, "rimRadius": 48, "faceRadius": 40, "faceEdge": {"color": "mauve", "width": 1.5},
             "glyph": {"translate": 27.2, "scale": 1.9}, "scallop": {"bumps": 20, "baseRadius": 47, "depth": 2.5, "points": 200},
             "locked": {"opacity": 0.4, "grayscale": 1}}, "stroke": 2, "areas": {}, "monthly": {"rim": "#D4A017"}, "glyphs": {}}
            """#
        #expect(throws: Medals.LoadError.badColour("mauve")) { try Medals(json: Data(json.utf8)) }
    }

    @Test @MainActor func aCoinRendersInEveryState() {
        let coins = [
            CoinMedalView(badgeID: "workouts_1", area: "training", size: 64),
            CoinMedalView(badgeID: "workouts_1", area: "training", size: 64, locked: true),
            CoinMedalView(badgeID: "workouts_1", area: "social", size: 64, monthly: true),
            CoinMedalView(badgeID: "nope", area: "unknown", size: 64),
        ]
        for coin in coins {
            let image = ImageRenderer(content: coin).uiImage
            #expect(image?.size == CGSize(width: 64, height: 64))
        }
    }

    /// A rendered coin is not blank: the rim, face and glyph put colour in the middle.
    @Test @MainActor func aCoinPutsColourOnTheFaceAndNothingOutsideTheRim() throws {
        let renderer = ImageRenderer(content: CoinMedalView(badgeID: "workouts_1", area: "training", size: 100))
        renderer.scale = 1
        let cgImage = try #require(renderer.uiImage?.cgImage)
        let data = try #require(cgImage.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[y * cgImage.bytesPerRow + x * (cgImage.bitsPerPixel / 8) + 3] }
        #expect(alpha(50, 30) > 200, "the face is opaque")
        #expect(alpha(0, 0) == 0, "the corner outside the rim is clear")
    }
}
