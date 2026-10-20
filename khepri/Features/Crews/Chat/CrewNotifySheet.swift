import SwiftUI

/// What this crew may notify you about, and for how long to mute it.
struct CrewNotifySheet: View {
    /// Saves the choice: `mutedUntil` nil clears any mute, as on the web.
    let onSave: (_ notify: String, _ mutedUntil: Date?) -> Void

    @State private var notify: String
    @State private var mute: Mute = .off
    @Environment(\.dismiss) private var dismiss

    /// The server's notify values. Anything else it sends reads as all.
    private static let levels: [(key: String, title: LocalizedStringKey)] = [
        ("all", "All messages"),
        ("mentions", "Mentions and replies"),
        ("none", "Nothing")
    ]

    enum Mute: CaseIterable, Hashable {
        case off, hour, day, week

        var title: LocalizedStringKey {
            switch self {
            case .off: "Don't mute"
            case .hour: "For an hour"
            case .day: "For a day"
            case .week: "For a week"
            }
        }

        func until(from now: Date) -> Date? {
            switch self {
            case .off: nil
            case .hour: now.addingTimeInterval(3600)
            case .day: now.addingTimeInterval(86400)
            case .week: now.addingTimeInterval(7 * 86400)
            }
        }
    }

    init(current: String?, onSave: @escaping (_ notify: String, _ mutedUntil: Date?) -> Void) {
        let known = Self.levels.contains { $0.key == current }
        _notify = State(initialValue: known ? current ?? "all" : "all")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Notifications", selection: $notify) {
                        ForEach(Self.levels, id: \.key) { level in
                            Text(level.title).tag(level.key)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Mute") {
                    Picker("Mute", selection: $mute) {
                        ForEach(Mute.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(notify, mute.until(from: Date()))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
