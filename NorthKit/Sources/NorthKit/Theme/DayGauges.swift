import SwiftUI

/// A 270° arc gauge, open at the bottom: the vitals strip on My Day.
public struct ArcGauge: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    public init(fraction: Double, color: Color, lineWidth: CGFloat = 5) {
        self.fraction = fraction
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            arc(to: 0.75).stroke(NorthColor.hairline, style: stroke)
            arc(to: 0.75 * clamped).stroke(color, style: stroke)
        }
        .rotationEffect(.degrees(135))
        .accessibilityHidden(true)
    }

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }
    private func arc(to end: Double) -> some Shape { Circle().trim(from: 0, to: end) }
}

/// One ring in a set of concentric progress rings.
public struct RingValue: Identifiable, Sendable {
    public let id: String
    public let fraction: Double
    public let color: Color

    public init(id: String, fraction: Double, color: Color) {
        self.id = id
        self.fraction = fraction
        self.color = color
    }
}

/// Concentric progress rings, outermost first: activity rings, macro rings.
public struct MultiRingView: View {
    let rings: [RingValue]
    let lineWidth: CGFloat
    let gap: CGFloat

    public init(rings: [RingValue], lineWidth: CGFloat = 8, gap: CGFloat = 2) {
        self.rings = rings
        self.lineWidth = lineWidth
        self.gap = gap
    }

    public var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                RingView(fraction: ring.fraction, color: ring.color, lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + gap))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single progress ring starting at twelve o'clock, over a faint track in
/// its own colour.
public struct RingView: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    public init(fraction: Double, color: Color, lineWidth: CGFloat = 8) {
        self.fraction = fraction
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// A night drawn as stage rows, awake at the top and deep at the bottom.
public struct Hypnogram: View {
    public struct Block: Identifiable, Sendable {
        public let id: Int
        public let row: Int // 0 = awake … 3 = deep
        public let start: Double // 0…1 across the night
        public let width: Double
        public let color: Color

        public init(id: Int, row: Int, start: Double, width: Double, color: Color) {
            self.id = id
            self.row = row
            self.start = start
            self.width = width
            self.color = color
        }
    }

    let blocks: [Block]

    public init(blocks: [Block]) { self.blocks = blocks }

    public var body: some View {
        GeometryReader { proxy in
            let rowHeight = proxy.size.height / 4
            ForEach(blocks) { block in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(block.color)
                    .frame(width: max(block.width * proxy.size.width, 2), height: rowHeight * 0.8)
                    .offset(x: block.start * proxy.size.width, y: CGFloat(block.row) * rowHeight)
            }
        }
        .accessibilityHidden(true)
    }
}
