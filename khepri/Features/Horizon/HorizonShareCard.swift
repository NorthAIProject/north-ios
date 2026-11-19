import NorthKit
import SwiftUI

/// The image a forecast is shared as: a fixed navy card at 4:5, like the
/// recap's. Lifts only: body weight and waist are not for a feed unless the
/// person puts them there. Ranges, never single numbers, each with its track
/// record and the disclaimer below: a shared forecast keeps what makes it
/// honest.
struct HorizonShareCard: View {
    let forecast: HorizonForecast

    /// Points; rendered at 3× for 1080 × 1350.
    static let size = RecapShareCard.size
    private static let ivory = RecapShareCard.ivory
    private static let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
    /// The most rows the card holds without crowding.
    static let maxRows = 3

    /// The lifts with a range to show.
    static func rows(_ forecast: HorizonForecast) -> [Row] {
        forecast.series.compactMap { series -> Row? in
            guard series.id.hasPrefix("lift:"), series.isReady, let far = series.points.last, far.offsetDays > 0,
                  let bar = series.bar(at: far.offsetDays) else { return nil }
            return Row(id: series.id, name: series.name, weeks: max(far.offsetDays / 7, 1),
                       range: "\(far.low.formatted(number))–\(far.high.formatted(number)) \(series.unit)", bar: bar,
                       record: series.trackRecord)
        }
        .prefix(maxRows)
        .map { $0 }
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let weeks: Int
        let range: String
        let bar: HorizonBar
        /// "Would have landed in range 5 of 6 times", when there is one.
        let record: String?
    }

    var body: some View {
        let rows = Self.rows(forecast)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                NorthBrand.markSmall
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(verbatim: "Khepri")
                    .font(.northDisplay(size: 17, relativeTo: .headline))
                    .tracking(1)
                    .foregroundStyle(Self.ivory)
            }
            Text("Where this is heading")
                .font(.northDisplay(size: 28, relativeTo: .title))
                .foregroundStyle(Self.ivory)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name)
                                .font(.system(size: 15, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(row.range)
                                .font(.system(size: 15))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Self.ivory)
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Self.ivory.opacity(0.14)).frame(height: 1)
                                Rectangle().fill(Self.ivory.opacity(0.6)).frame(width: 1, height: 10)
                                    .offset(x: width * row.bar.now)
                                Capsule().fill(Self.ivory.opacity(0.9))
                                    .frame(width: max(width * (row.bar.high - row.bar.low), 6), height: 6)
                                    .offset(x: width * row.bar.low)
                            }
                            .frame(height: 10)
                        }
                        .frame(height: 10)
                        Text("Est. 1RM in \(row.weeks) weeks")
                            .font(.system(size: 12))
                            .foregroundStyle(Self.ivory.opacity(0.7))
                        if let record = row.record {
                            Text(record)
                                .font(.system(size: 12))
                                .foregroundStyle(Self.ivory.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 12)

            Text(forecast.disclaimer)
                .font(.system(size: 11))
                .foregroundStyle(Self.ivory.opacity(0.7))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "kheprios.com")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Self.ivory.opacity(0.7))
                .padding(.top, 10)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.106, green: 0.165, blue: 0.251), Color(red: 0.043, green: 0.067, blue: 0.110)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }

    /// The card as an image; nil when there is nothing to forecast or it
    /// could not be drawn.
    @MainActor
    static func render(_ forecast: HorizonForecast) -> UIImage? {
        guard forecast.isReady, forecast.scenario.isPlain, !rows(forecast).isEmpty else { return nil }
        let renderer = ImageRenderer(content: HorizonShareCard(forecast: forecast))
        renderer.scale = 3
        return renderer.uiImage
    }
}
