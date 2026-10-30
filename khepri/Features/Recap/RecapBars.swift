import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// One stacked bar per day: a segment each for training, food and a
/// check-in. Every segment is one unit, so the bar says which parts of the
/// day showed up, not how much each logged.
struct RecapBars: View {
    let days: [RecapDay]
    var height: CGFloat = 120
    /// Weekday letters under a week; a 30-day chart is too dense for labels.
    var showsLabels = true
    /// The fixed palette for the share image, which is always drawn dark.
    var palette: RecapPalette = .app

    var body: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(days, id: \.date) { day in
                    if day.areas == 0 {
                        // A thin track keeps empty days in the row.
                        BarMark(x: .value("Day", day.calendarDate, unit: .day), y: .value("Areas", 0.08))
                            .foregroundStyle(palette.track)
                            .cornerRadius(2)
                    } else {
                        ForEach(RecapArea.allCases) { area in
                            if area.present(on: day) {
                                BarMark(x: .value("Day", day.calendarDate, unit: .day), y: .value("Areas", 1))
                                    .foregroundStyle(palette.color(area))
                                    .cornerRadius(3)
                            }
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...3)
            .frame(height: height)

            if showsLabels && days.count <= 7 {
                HStack(spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        Text(day.calendarDate, format: .dateTime.weekday(.narrow))
                            .font(.north(.caption))
                            .foregroundStyle(palette.label)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let active = days.count(where: { $0.areas > 0 })
        return String(localized: "Active on \(active) of \(days.count) days")
    }
}

/// What a day can have.
enum RecapArea: CaseIterable, Identifiable {
    case training, food, checkIn

    var id: Self { self }

    var title: String {
        switch self {
        case .training: String(localized: "Training")
        case .food: String(localized: "Food")
        case .checkIn: String(localized: "Check-in")
        }
    }

    func present(on day: RecapDay) -> Bool {
        switch self {
        case .training: day.trained
        case .food: day.ate
        case .checkIn: day.checkedIn
        }
    }
}

struct RecapPalette {
    let training: Color
    let food: Color
    let checkIn: Color
    let track: Color
    let label: Color

    func color(_ area: RecapArea) -> Color {
        switch area {
        case .training: training
        case .food: food
        case .checkIn: checkIn
        }
    }

    static let app = RecapPalette(training: NorthColor.signal, food: NorthColor.Day.food, checkIn: NorthColor.ember,
                                  track: Color(.tertiarySystemFill), label: .secondary)

    /// On the navy share card: ivory segments, with Solar Gold for the
    /// check-ins so the one accent marks the habit the card celebrates.
    static let share = RecapPalette(training: RecapShareCard.ivory, food: RecapShareCard.ivory.opacity(0.55),
                                    checkIn: Color(red: 0.910, green: 0.714, blue: 0.361),
                                    track: RecapShareCard.ivory.opacity(0.14), label: RecapShareCard.ivory.opacity(0.7))
}

/// The three areas as coloured dots with names.
struct RecapLegend: View {
    var palette: RecapPalette = .app

    var body: some View {
        HStack(spacing: 14) {
            ForEach(RecapArea.allCases) { area in
                HStack(spacing: 5) {
                    Circle().fill(palette.color(area)).frame(width: 8, height: 8)
                    Text(area.title).font(.north(.footnote)).foregroundStyle(palette.label)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
