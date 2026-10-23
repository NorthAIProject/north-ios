import SwiftUI

/// One badge as a coin: a metallic rim, a deep face in the area's colour and a
/// white glyph. Monthly medals get a gold scalloped rim; a locked one is
/// greyscale and faded. It draws what the web's `medal.Coin` draws, from the
/// same `medals.json`.
public struct CoinMedalView: View {
    private let badgeID: String
    private let area: String
    private let size: CGFloat
    private let locked: Bool
    private let monthly: Bool

    public init(badgeID: String, area: String, size: CGFloat, locked: Bool = false, monthly: Bool = false) {
        self.badgeID = badgeID
        self.area = area
        self.size = size
        self.locked = locked
        self.monthly = monthly
    }

    public var body: some View {
        let medals = Medals.shared
        let geometry = medals.geometry
        let style = medals.style(forArea: area)
        let glyph = medals.glyphPaths(for: badgeID)
        Canvas { context, canvasSize in
            let mid = geometry.viewBox / 2
            context.scaleBy(x: canvasSize.width / geometry.viewBox, y: canvasSize.height / geometry.viewBox)

            let rim = monthly ? medals.scallop() : Path(ellipseIn: Self.square(around: mid, radius: geometry.rimRadius))
            let box = rim.boundingRect
            let rimColour = monthly ? medals.monthlyRim : style.rim
            let gradient = Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: rimColour, location: 0.35),
                .init(color: style.fill, location: 0.7),
                .init(color: rimColour, location: 1),
            ])
            context.fill(rim, with: .linearGradient(gradient, startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))

            let face = Path(ellipseIn: Self.square(around: mid, radius: geometry.faceRadius))
            context.fill(face, with: .color(style.fill))
            context.stroke(face, with: .color(geometry.faceEdgeColor), lineWidth: geometry.faceEdgeWidth)

            context.translateBy(x: geometry.glyphTranslate, y: geometry.glyphTranslate)
            context.scaleBy(x: geometry.glyphScale, y: geometry.glyphScale)
            for path in glyph {
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: medals.stroke, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .grayscale(locked ? geometry.lockedGrayscale : 0)
        .opacity(locked ? geometry.lockedOpacity : 1)
    }

    private static func square(around mid: Double, radius: Double) -> CGRect {
        CGRect(x: mid - radius, y: mid - radius, width: radius * 2, height: radius * 2)
    }
}

#Preview("Coins") {
    HStack {
        CoinMedalView(badgeID: "workouts_1", area: "training", size: 64)
        CoinMedalView(badgeID: "streak_30", area: "consistency", size: 64, locked: true)
        CoinMedalView(badgeID: "workouts_1", area: "social", size: 64, monthly: true)
        CoinMedalView(badgeID: "nope", area: "unknown", size: 64)
    }
    .padding()
}
