import SwiftUI

/// Reports a message: one of the server's reasons and an optional note.
struct CrewReportSheet: View {
    let onSend: (_ reason: String, _ note: String?) -> Void

    @State private var reason: String?
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    /// The server's reason keys, in the web's order.
    private static let reasons: [(key: String, title: LocalizedStringKey)] = [
        ("spam", "Spam"),
        ("harassment", "Harassment or bullying"),
        ("hate", "Hate"),
        ("sexual", "Sexual content"),
        ("violence", "Violence or threats"),
        ("self_harm", "Self-harm"),
        ("other", "Something else")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Report message", selection: $reason) {
                        ForEach(Self.reasons, id: \.key) { item in
                            Text(item.title).tag(Optional(item.key))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text("The message disappears for you right away, and we review every report.")
                }
                Section {
                    TextField("Anything to add? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("Send report") {
                        guard let reason else { return }
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSend(reason, trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .disabled(reason == nil)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Report message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
