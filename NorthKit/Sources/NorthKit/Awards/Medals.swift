import Foundation
import SwiftUI

/// The coin medals' colours, geometry and glyph paths, decoded from
/// `medals.json`. The web app owns that file (`docs/medals/medals.json`) and
/// `scripts/sync-openapi.sh` copies it here, so a coin is the same on both.
public struct Medals: Sendable {
    /// The face and rim colours of one area.
    public struct AreaStyle: Equatable, Sendable {
        public let fillHex: String
        public let rimHex: String
        public let fill: Color
        public let rim: Color
    }

    struct Geometry: Sendable {
        var viewBox: Double
        var rimRadius: Double
        var faceRadius: Double
        var faceEdgeColor: Color
        var faceEdgeWidth: Double
        var glyphTranslate: Double
        var glyphScale: Double
        var scallopBumps: Int
        var scallopBaseRadius: Double
        var scallopDepth: Double
        var scallopPoints: Int
        var lockedOpacity: Double
        var lockedGrayscale: Double
    }

    public enum LoadError: Error, Equatable {
        case missingResource
        case badColour(String)
    }

    /// The area an unknown name draws as. The web keeps its slate for body.
    static let fallbackArea = "body"

    /// The medals bundled with NorthKit.
    public static let shared: Medals = {
        guard let url = NorthKitBundle.bundle.url(forResource: "medals", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let medals = try? Medals(json: data)
        else { preconditionFailure("NorthKit's medals.json is missing or malformed") }
        return medals
    }()

    let geometry: Geometry
    let stroke: Double
    let monthlyRim: Color
    public let monthlyRimHex: String
    public let areas: [String: AreaStyle]
    private let glyphs: [String: [Path]]
    /// Badge ids with a glyph path that did not parse, or no paths at all.
    /// Such a coin draws blank, so a test holds this empty.
    public let brokenGlyphs: [String]

    /// Decodes a `medals.json`. Throws when it is malformed or a colour cannot be read.
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        func colour(_ text: String) throws -> Color {
            guard let rgba = RGBA(css: text) else { throw LoadError.badColour(text) }
            return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        }
        let coin = file.coin
        geometry = Geometry(
            viewBox: coin.viewBox, rimRadius: coin.rimRadius, faceRadius: coin.faceRadius,
            faceEdgeColor: try colour(coin.faceEdge.color), faceEdgeWidth: coin.faceEdge.width,
            glyphTranslate: coin.glyph.translate, glyphScale: coin.glyph.scale,
            scallopBumps: coin.scallop.bumps, scallopBaseRadius: coin.scallop.baseRadius,
            scallopDepth: coin.scallop.depth, scallopPoints: coin.scallop.points,
            lockedOpacity: coin.locked.opacity, lockedGrayscale: coin.locked.grayscale
        )
        stroke = file.stroke
        monthlyRim = try colour(file.monthly.rim)
        monthlyRimHex = file.monthly.rim
        areas = try file.areas.mapValues {
            AreaStyle(fillHex: $0.fill, rimHex: $0.rim, fill: try colour($0.fill), rim: try colour($0.rim))
        }
        // A glyph that fails to parse is dropped: the coin still reads by colour.
        let parsed = file.glyphs.mapValues { $0.compactMap { try? Path(SVGPath.parse($0)) } }
        glyphs = parsed
        brokenGlyphs = file.glyphs.filter { id, paths in
            paths.isEmpty || parsed[id]?.count != paths.count
        }.keys.sorted()
    }

    /// The colours for `area`; a name this build has never seen draws as slate.
    public func style(forArea area: String) -> AreaStyle {
        areas[area] ?? areas[Self.fallbackArea] ?? AreaStyle(
            fillHex: "#475569", rimHex: "#9AA2AC",
            fill: Color(.sRGB, red: 0.278, green: 0.333, blue: 0.412), rim: Color(.sRGB, red: 0.604, green: 0.635, blue: 0.675)
        )
    }

    /// Whether the file draws a glyph for this badge.
    public func hasGlyph(for badgeID: String) -> Bool { !(glyphs[badgeID] ?? []).isEmpty }

    func glyphPaths(for badgeID: String) -> [Path] { glyphs[badgeID] ?? [] }

    /// The outline of a coin with a ring of bumps, in the viewBox.
    func scallop() -> Path {
        let g = geometry
        let mid = g.viewBox / 2
        var path = Path()
        for index in 0..<g.scallopPoints {
            let angle = 2 * Double.pi * Double(index) / Double(g.scallopPoints)
            let radius = g.scallopBaseRadius + g.scallopDepth * cos(Double(g.scallopBumps) * angle)
            let point = CGPoint(x: mid + radius * cos(angle), y: mid + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private struct File: Decodable {
        struct Area: Decodable { let fill: String; let rim: String }
        struct Coin: Decodable {
            struct Edge: Decodable { let color: String; let width: Double }
            struct Glyph: Decodable { let translate: Double; let scale: Double }
            struct Scallop: Decodable { let bumps: Int; let baseRadius: Double; let depth: Double; let points: Int }
            struct Locked: Decodable { let opacity: Double; let grayscale: Double }
            let viewBox: Double
            let rimRadius: Double
            let faceRadius: Double
            let faceEdge: Edge
            let glyph: Glyph
            let scallop: Scallop
            let locked: Locked
        }
        struct Monthly: Decodable { let rim: String }
        let coin: Coin
        let stroke: Double
        let areas: [String: Area]
        let monthly: Monthly
        let glyphs: [String: [String]]
    }
}

/// A CSS colour as `#RRGGBB` or `rgba(r,g,b,a)`.
struct RGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init?(css text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#"), text.count == 7, let value = UInt32(text.dropFirst(), radix: 16) {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else if text.hasPrefix("rgba("), text.hasSuffix(")") {
            let parts = text.dropFirst(5).dropLast().split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4, let r = parts[0], let g = parts[1], let b = parts[2], let a = parts[3] else { return nil }
            red = r / 255
            green = g / 255
            blue = b / 255
            alpha = a
        } else {
            return nil
        }
    }
}
