import SwiftUI

/// A short text field under a small label, for the compact columns of an
/// imported exercise.
struct ImportLabeledField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("—", text: $text).keyboardType(keyboard)
        }
    }
}
