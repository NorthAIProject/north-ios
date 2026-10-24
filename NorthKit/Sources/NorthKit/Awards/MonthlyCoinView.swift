import SwiftUI

/// The monthly challenge coin: a gold scalloped rim, a deep face, the month
/// above centre and the target number below it. It draws what the web's
/// `medal.MonthlyCoin` draws, every colour and position read from `medals.json`.
public struct MonthlyCoinView: View {
    private let month: String
    private let target: Int
    private let size: CGFloat
    private let locked: Bool
    @Environment(\.locale) private var locale

    /// - Parameter month: the local month as `YYYY-MM`.
    public init(month: String, target: Int, size: CGFloat, locked: Bool = false) {
        self.month = month
        self.target = target
        self.size = size
        self.locked = locked
    }

    /// The short month, upper-cased in `locale`: "OCT" in English, "OUT" in
    /// Portuguese. An unreadable `YYYY-MM` gives an empty label.
    nonisolated public static func monthLabel(_ month: String, locale: Locale) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 15)) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        let short = formatter.string(from: date).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return short.uppercased(with: locale)
    }

    public var body: some View {
        let medals = Medals.shared
        let geometry = medals.geometry
        let text = medals.monthlyText
        let label = Self.monthLabel(month, locale: locale)
        Canvas { context, canvasSize in
            let mid = geometry.viewBox / 2
            context.scaleBy(x: canvasSize.width / geometry.viewBox, y: canvasSize.height / geometry.viewBox)

            let rim = medals.scallop()
            let box = rim.boundingRect
            let gradient = Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: medals.monthlyRim, location: 0.35),
                .init(color: medals.monthlyFill, location: 0.7),
                .init(color: medals.monthlyRim, location: 1),
            ])
            context.fill(rim, with: .linearGradient(gradient, startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))

            let face = Path(ellipseIn: CGRect(x: mid - geometry.faceRadius, y: mid - geometry.faceRadius,
                                              width: geometry.faceRadius * 2, height: geometry.faceRadius * 2))
            context.fill(face, with: .color(medals.monthlyFill))
            context.stroke(face, with: .color(geometry.faceEdgeColor), lineWidth: geometry.faceEdgeWidth)

            if !label.isEmpty {
                Self.draw(label, size: text.monthSize, y: text.monthY, in: &context, mid: mid, text: text)
                Self.draw(String(target), size: text.numberSize(forTarget: target), y: text.numberY, in: &context, mid: mid, text: text)
            }
        }
        .frame(width: size, height: size)
        .grayscale(locked ? geometry.lockedGrayscale : 0)
        .opacity(locked ? geometry.lockedOpacity : 1)
    }

    /// Draws one line with its alphabetic baseline (or, when the json says so, its centre) at `y`.
    private static func draw(_ string: String, size: Double, y: Double, in context: inout GraphicsContext,
                             mid: Double, text: Medals.MonthlyText) {
        let font = Font.system(size: size, weight: text.weight, design: text.design)
        let resolved = context.resolve(Text(string).font(font).foregroundColor(text.color))
        let measured = resolved.measure(in: CGSize(width: 1000, height: 1000))
        let top = text.baseline ? y - resolved.firstBaseline(in: measured) : y - measured.height / 2
        let left = switch text.anchor {
        case "start": mid
        case "end": mid - measured.width
        default: mid - measured.width / 2
        }
        context.draw(resolved, at: CGPoint(x: left, y: top), anchor: .topLeading)
    }
}

#Preview("Monthly coins") {
    HStack {
        MonthlyCoinView(month: "2026-10", target: 12, size: 96)
        MonthlyCoinView(month: "2026-09", target: 150, size: 96)
        MonthlyCoinView(month: "2026-09", target: 12, size: 96, locked: true)
    }
    .padding()
}
