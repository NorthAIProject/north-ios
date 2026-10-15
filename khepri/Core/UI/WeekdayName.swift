import Foundation

/// Plan days arrive from the server as English names ("Monday") and go back
/// to it unchanged. The screen shows them in the reader's language.
enum WeekdayName {
    private static let english = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// "Monday" → "Lunes" in Spanish. A name the app does not recognise is
    /// shown as it came.
    static func display(_ day: String, calendar: Calendar = .current) -> String {
        guard let index = english.firstIndex(of: day.trimmingCharacters(in: .whitespaces).lowercased()) else {
            return day
        }
        let name = calendar.standaloneWeekdaySymbols[index]
        return name.prefix(1).uppercased(with: calendar.locale) + name.dropFirst()
    }

    /// The one-letter chip label: "L" for lunes, "S" for segunda-feira.
    static func initial(_ day: String, calendar: Calendar = .current) -> String {
        String(display(day, calendar: calendar).prefix(1))
    }
}
