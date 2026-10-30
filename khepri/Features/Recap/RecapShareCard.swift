import NorthAPI
import NorthKit
import SwiftUI

/// The image a recap is shared as: a fixed navy card at 4:5, the size a
/// feed post or a message preview shows whole. It ignores the app's
/// appearance and text size so every shared image looks the same.
struct RecapShareCard: View {
    let recap: Recap
    let range: RecapRange

    /// Points; rendered at 3× for 1080 × 1350.
    static let size = CGSize(width: 360, height: 450)
    /// Warm Ivory, the brand's light ink on navy.
    static let ivory = Color(red: 0.965, green: 0.949, blue: 0.918)

    var body: some View {
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
            Text(range.heading)
                .font(.northDisplay(size: 32, relativeTo: .title))
                .foregroundStyle(Self.ivory)
                .padding(.top, 12)
            Text(recap.period)
                .font(.system(size: 15))
                .foregroundStyle(Self.ivory.opacity(0.75))
                .padding(.top, 2)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Figure(value: recap.totals.activeDays, label: String(localized: "Active days"))
                    Figure(value: recap.totals.workouts, label: String(localized: "Workouts"))
                }
                GridRow {
                    Figure(value: recap.totals.checkIns, label: String(localized: "Check-ins"))
                    Figure(value: recap.totals.sets, label: String(localized: "Sets"))
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 16)

            RecapBars(days: recap.days, height: 64, showsLabels: range == .week, palette: .share)
            RecapLegend(palette: .share)
                .padding(.top, 10)

            Text(verbatim: "kheprios.com")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Self.ivory.opacity(0.7))
                .padding(.top, 14)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            // Armor Navy to Obsidian Navy (docs/brand in north-web-app).
            LinearGradient(colors: [Color(red: 0.106, green: 0.165, blue: 0.251), Color(red: 0.043, green: 0.067, blue: 0.110)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }

    /// The card as an image, or nil if it could not be drawn.
    @MainActor
    static func render(_ recap: Recap, range: RecapRange) -> UIImage? {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap, range: range))
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct Figure: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value, format: .number)
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(RecapShareCard.ivory)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(RecapShareCard.ivory.opacity(0.75))
        }
        .frame(minWidth: 130, alignment: .leading)
    }
}
