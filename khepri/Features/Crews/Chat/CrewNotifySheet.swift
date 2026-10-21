import SwiftUI

/// What this crew may notify you about, and for how long to mute it.
struct CrewNotifySheet: View {
    /// Saves the choice: `mutedUntil` nil clears any mute, as on the web. An
    /// active mute is offered first and kept unless another choice is made.
    let onSave: (_ notify: String, _ mutedUntil: Date?) -> Void

    @State private var notify: String
    @State private var mute: Mute
    @Environment(\.dismiss) private var dismiss

    /// The server's notify values. Anything else it sends reads as all.
    private static let levels: [(key: String, title: LocalizedStringKey)] = [
        ("all", "All messages"),
        ("mentions", "Mentions and replies"),
        ("none", "Nothing")
    ]

    enum Mute: Hashable {
        /// The mute already set, kept as it is.
        case current(Date)
        case off, hour, day, week

        /// An active mute first, so saving another setting does not lift it.
        static func choices(mutedUntil: Date?, now: Date) -> [Mute] {
            let active = initial(mutedUntil: mutedUntil, now: now)
            return (active == .off ? [] : [active]) + [.off, .hour, .day, .week]
        }

        static func initial(mutedUntil: Date?, now: Date) -> Mute {
            guard let mutedUntil, mutedUntil > now else { return .off }
            return .current(mutedUntil)
        }

        var title: Text {
            switch self {
            case .current(let date): Text("Muted until \(date, format: .dateTime.weekday().hour().minute())")
            case .off: Text("Don't mute")
            case .hour: Text("For an hour")
            case .day: Text("For a day")
            case .week: Text("For a week")
            }
        }

        func until(from now: Date) -> Date? {
            switch self {
            case .current(let date): date
            case .off: nil
            case .hour: now.addingTimeInterval(3600)
            case .day: now.addingTimeInterval(86400)
            case .week: now.addingTimeInterval(7 * 86400)
            }
        }
    }

    private let muteChoices: [Mute]

    init(
        current: String?, mutedUntil: Date?,
        onSave: @escaping (_ notify: String, _ mutedUntil: Date?) -> Void
    ) {
        let known = Self.levels.contains { $0.key == current }
        _notify = State(initialValue: known ? current ?? "all" : "all")
        let now = Date()
        _mute = State(initialValue: Mute.initial(mutedUntil: mutedUntil, now: now))
        muteChoices = Mute.choices(mutedUntil: mutedUntil, now: now)
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
                        ForEach(muteChoices, id: \.self) { option in
                            option.title.tag(option)
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
