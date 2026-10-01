import SwiftUI

/// The bounds for amounts typed by hand. Wide enough for a big bottle or a
/// strong pre-workout, narrow enough that a stray extra zero is refused
/// before it skews a week of totals.
enum TypedAmount {
    static let waterMl = 1...5000
    static let caffeineMg = 1...1000

    /// The whole number in `text` when it falls inside `range`, else nil.
    static func parse(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(value) else { return nil }
        return value
    }
}

/// "Other" next to the water presets: any amount in millilitres.
struct WaterAmountField: View {
    let onAdd: (Int) -> Void
    @State private var text = ""

    var body: some View {
        let ml = TypedAmount.parse(text, in: TypedAmount.waterMl)
        HStack {
            TextField("Other amount", text: $text)
                .keyboardType(.numberPad)
            Text("ml").foregroundStyle(.secondary)
            Button("Add") {
                guard let ml else { return }
                text = ""
                onAdd(ml)
            }
            .buttonStyle(.bordered)
            .disabled(ml == nil)
        }
    }
}
