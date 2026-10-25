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
            let hex = /^#[0-9A-Fa-f]{6}$/
            #expect(style.fillHex.wholeMatch(of: hex) != nil && style.rimHex.wholeMatch(of: hex) != nil, "\(area): \(style)")
            #expect(style.fillHex != style.rimHex)
        }
        #expect(Medals.shared.monthlyRimHex.wholeMatch(of: /^#[0-9A-Fa-f]{6}$/) != nil)
    }

    @Test func theMonthlyCoinDecodesItsFillAndText() {
        let medals = Medals.shared
        #expect(medals.monthlyFillHex == "#1E3A5F" && medals.monthlyRimHex == "#D4A017")
        let text = medals.monthlyText
        #expect(text.monthSize == 13 && text.monthY == 40 && text.numberSize == 34 && text.numberY == 71)
        #expect(text.fontWeight == 700 && text.weight == .bold && text.design == .rounded)
        #expect(text.anchor == "middle" && text.baseline)
        #expect(text.numberSize(forTarget: 99) == 34)
        #expect(text.numberSize(forTarget: 100) == 25.5)
    }

    @Test func anUnknownAreaFallsBackToSlate() {
        let slate = Medals.shared.style(forArea: "body")
        #expect(Medals.shared.style(forArea: "telepathy") == slate)
        #expect(slate.fillHex == "#475569")
    }

    @Test func everyGlyphPathParses() {
        #expect(Medals.shared.brokenGlyphs.isEmpty, "blank coins: \(Medals.shared.brokenGlyphs)")
    }

    @Test func aBadgeWithoutAGlyphStillDraws() {
        #expect(!Medals.shared.hasGlyph(for: "badge_from_the_future"))
    }

    @Test func aMalformedColourIsRejected() {
        let json = #"""
            {"coin": {"viewBox": 100, "rimRadius": 48, "faceRadius": 40, "faceEdge": {"color": "mauve", "width": 1.5},
             "glyph": {"translate": 27.2, "scale": 1.9}, "scallop": {"bumps": 20, "baseRadius": 47, "depth": 2.5, "points": 200},
             "locked": {"opacity": 0.4, "grayscale": 1}}, "stroke": 2, "areas": {}, "monthly": {"rim": "#D4A017", "fill": "#1E3A5F", "text": {"color": "#FFFFFF", "monthSize": 13, "monthY": 40, "numberSize": 34, "numberY": 71, "numberWideFrom": 100, "numberWideScale": 0.75, "fontWeight": 700, "fontFamily": "rounded", "anchor": "middle", "baseline": true}}, "glyphs": {}}
            """#
        #expect(throws: Medals.LoadError.badColour("mauve")) { try Medals(json: Data(json.utf8)) }
    }

    @Test @MainActor func aCoinRendersInEveryState() {
        let coins = [
            CoinMedalView(badgeID: "workouts_1", area: "training", size: 64),
            CoinMedalView(badgeID: "workouts_1", area: "training", size: 64, locked: true),
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

    @Test func theMonthLabelIsTheShortMonthInCapitals() {
        #expect(MonthlyCoinView.monthLabel("2026-10", locale: Locale(identifier: "en")) == "OCT")
        #expect(MonthlyCoinView.monthLabel("2026-10", locale: Locale(identifier: "pt-PT")) == "OUT")
        #expect(MonthlyCoinView.monthLabel("2026-10", locale: Locale(identifier: "pt-BR")) == "OUT")
        #expect(MonthlyCoinView.monthLabel("2026-09", locale: Locale(identifier: "es")) == "SEPT")
        #expect(MonthlyCoinView.monthLabel("2026-01", locale: Locale(identifier: "en")) == "JAN")
        #expect(MonthlyCoinView.monthLabel("nonsense", locale: Locale(identifier: "en")).isEmpty)
        #expect(MonthlyCoinView.monthLabel("2026-13", locale: Locale(identifier: "en")).isEmpty)
    }

    /// The monthly coin puts the white month and number on its face; the corner stays clear.
    @Test @MainActor func theMonthlyCoinDrawsTextOnItsFace() throws {
        let renderer = ImageRenderer(content: MonthlyCoinView(month: "2026-10", target: 12, size: 100).environment(\.locale, Locale(identifier: "en")))
        renderer.scale = 1
        let cgImage = try #require(renderer.uiImage?.cgImage)
        let data = try #require(cgImage.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let stride = cgImage.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let i = y * cgImage.bytesPerRow + x * stride
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }
        #expect(pixel(0, 0).a == 0)
        var white = 0
        for y in 45...75 { for x in 30...70 where pixel(x, y).r > 230 && pixel(x, y).g > 230 && pixel(x, y).b > 230 { white += 1 } }
        #expect(white > 20, "the target number is drawn in white on the face")
        #expect(pixel(50, 85).b > pixel(50, 85).r, "the face below the number is the deep blue")
    }
}
