import NorthAPI
import SwiftUI

/// Settings, presented from More: one row per card on the web page, then the
/// tour, sign-out and account deletion.
struct SettingsScreen: View {
    let user: APIUser
    @Environment(AppModel.self) private var app
    @Environment(GuidedTour.self) private var tour
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false
    @State private var deleting = false

    var service: SettingsServicing = SettingsService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { ProfileSettings(service: service) } label: {
                        LabeledContent {
                            Text(user.email)
                        } label: {
                            Label(user.displayName.isEmpty ? "Account" : user.displayName, systemImage: "person.crop.circle")
                        }
                    }
                }

                Section("Coach") {
                    NavigationLink { CoachingSettings(service: service) } label: {
                        Label("Coaching Style", systemImage: "quote.bubble")
                    }
                    NavigationLink { AIProviderSettings(service: service) } label: {
                        Label("AI Provider", systemImage: "cpu")
                    }
                }

                Section("Connections") {
                    NavigationLink { HealthSettings() } label: {
                        Label("Apple Health", systemImage: "heart.text.square")
                    }
                    NavigationLink { StravaSettings() } label: {
                        Label("Strava", systemImage: "figure.run")
                    }
                    NavigationLink { AgentConnections(service: service) } label: {
                        Label("Agents", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    NavigationLink { TelegramSettings(service: service) } label: {
                        Label("Telegram", systemImage: "paperplane")
                    }
                    NavigationLink { CalendarSettings(service: service) } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                }

                Section("App") {
                    NavigationLink { NotificationSettings(service: service) } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    NavigationLink { PreferenceSettings(service: service) } label: {
                        Label("Units", systemImage: "ruler")
                    }
                    Button {
                        Task {
                            await tour.restart()
                            dismiss()
                        }
                    } label: {
                        Label("Show Me Around", systemImage: "hand.point.up.left")
                    }
                    ReviewSettingsRows()
                }

                Section {
                    Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    Button("Delete Account", role: .destructive) { deleting = true }
                } footer: {
                    Text("Version \(Bundle.main.versionDescription)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Sign out of Khepri?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
            }
            .sheet(isPresented: $deleting) {
                DeleteAccountSheet(email: user.email, service: service) {
                    Task { await app.signOut() }
                }
            }
        }
    }
}

extension Bundle {
    /// "1.0 (42)"
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Loading and saving

/// The load-edit-save cycle every settings card shares: fetch once, edit a
/// local copy, send it back, show the server's version (or its reason).
@MainActor
@Observable
final class Editable<Value: Equatable> {
    var value: Value?
    private(set) var saved: Value?
    private(set) var error: String?
    private(set) var isSaving = false

    var hasChanges: Bool { value != nil && value != saved }

    func load(_ fetch: () async throws -> Value) async {
        do {
            let fresh = try await fetch()
            value = fresh
            saved = fresh
            error = nil
        } catch {
            if value == nil { self.error = error.localizedDescription }
        }
    }

    /// - Returns: whether the server accepted it.
    @discardableResult
    func save(_ send: (Value) async throws -> Value) async -> Bool {
        guard let value else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let stored = try await send(value)
            self.value = stored
            saved = stored
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func fail(_ message: String) { error = message }
}

/// Shows a card's content once loaded, a spinner before, and the error.
struct Loaded<Value: Equatable, Content: View>: View {
    let editable: Editable<Value>
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value = editable.value {
            content(value)
        } else if let error = editable.error {
            ContentUnavailableView("Could not load", systemImage: "wifi.exclamationmark", description: Text(error))
        } else {
            ProgressView()
        }
    }
}

// MARK: - Profile

private struct ProfileSettings: View {
    let service: SettingsServicing
    @State private var profile = Editable<SettingsModel.Profile>()

    var body: some View {
        Loaded(editable: profile) { _ in
            Form {
                Section {
                    TextField("Name", text: bind(\.displayName))
                    LabeledContent("Email", value: profile.value?.email ?? "")
                }
                Section {
                    LabeledContent("Time Zone", value: profile.value?.timezone ?? "")
                    if profile.value?.timezone != TimeZone.current.identifier {
                        Button("Use This iPhone's (\(TimeZone.current.identifier))") {
                            profile.value?.timezone = TimeZone.current.identifier
                        }
                    }
                } footer: {
                    Text("Check-ins, reminders and reports follow this time zone.")
                }
                if let error = profile.error { ErrorRow(error) }
            }
        }
        .navigationTitle("Account")
        .saveToolbar(profile) { try await service.save($0) }
        .task { await profile.load(service.profile) }
    }

    private func bind(_ keyPath: WritableKeyPath<SettingsModel.Profile, String>) -> Binding<String> {
        Binding(get: { profile.value?[keyPath: keyPath] ?? "" }, set: { profile.value?[keyPath: keyPath] = $0 })
    }
}

// MARK: - Coaching style

private struct CoachingSettings: View {
    let service: SettingsServicing
    @State private var profile = Editable<SettingsModel.Profile>()

    private typealias Tone = SettingsModel.Profile.CoachingTonePayload

    var body: some View {
        Loaded(editable: profile) { value in
            Form {
                Section {
                    ForEach(CoachingStyle.allCases.filter { $0 != .custom }) { style in
                        Button {
                            profile.value?.coachingStyle = style.detail
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(style.title).foregroundStyle(.primary)
                                    Text(style.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if value.coachingStyle == style.detail {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        // A Form button tints its whole label; these rows
                        // read as choices, so only the checkmark is tinted.
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(value.coachingStyle == style.detail ? .isSelected : [])
                    }
                } header: {
                    Text("Style")
                }

                Section {
                    HStack(alignment: .top) {
                        TextField("Or describe it in your own words", text: coachingStyle, axis: .vertical)
                            .lineLimit(2...6)
                        DictationButton(text: coachingStyle, font: .body)
                    }
                } footer: {
                    Text("Your coach follows this on the web, in Telegram and here.")
                }

                Section("Tone") {
                    Picker("Tone", selection: Binding(
                        get: { profile.value?.coachingTone ?? .direct },
                        set: { profile.value?.coachingTone = $0 }
                    )) {
                        Text("Direct").tag(Tone.direct)
                        Text("Warm").tag(Tone.warm)
                        Text("Analytical").tag(Tone.analytical)
                        Text("Tough Love").tag(Tone.toughLove)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let error = profile.error { ErrorRow(error) }
            }
        }
        .navigationTitle("Coaching Style")
        .saveToolbar(profile) { try await service.save($0) }
        .task { await profile.load(service.profile) }
    }

    private var coachingStyle: Binding<String> {
        Binding(get: { profile.value?.coachingStyle ?? "" }, set: { profile.value?.coachingStyle = $0 })
    }
}

// MARK: - Preferences

private struct PreferenceSettings: View {
    let service: SettingsServicing
    @State private var preferences = Editable<SettingsModel.Preferences>()

    var body: some View {
        Loaded(editable: preferences) { _ in
            Form {
                Picker("Units", selection: Binding(
                    get: { preferences.value?.unitsSystem ?? .metric },
                    set: { preferences.value?.unitsSystem = $0 }
                )) {
                    Text("Metric").tag(SettingsModel.Preferences.UnitsSystemPayload.metric)
                    Text("Imperial").tag(SettingsModel.Preferences.UnitsSystemPayload.imperial)
                }
                .pickerStyle(.segmented)
                if let error = preferences.error { ErrorRow(error) }
            }
        }
        .navigationTitle("Units")
        .task { await preferences.load(service.preferences) }
        // One control, so it saves as it changes rather than behind a button.
        .onChange(of: preferences.value?.unitsSystem) { old, new in
            guard old != nil, new != old else { return }
            Task { await preferences.save { try await service.save($0) } }
        }
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    let service: SettingsServicing
    @State private var settings = Editable<SettingsModel.NotificationSettings>()

    private typealias Cadence = SettingsModel.NotificationSettings.StatsDigestCadencePayload

    var body: some View {
        Loaded(editable: settings) { value in
            Form {
                Section {
                    Toggle("Missed check-in", isOn: bind(\.nudgeMissedCheckIn))
                    Toggle("Goal deadlines", isOn: bind(\.nudgeGoalDeadline))
                    Toggle("Training reminders", isOn: bind(\.trainingReminders))
                    Toggle("Coach activity", isOn: bind(\.coachActivity))
                } header: {
                    Text("Nudges")
                }

                Section {
                    Toggle("Daily briefing", isOn: bind(\.dailyBriefingAuto))
                    Toggle("Weekly report", isOn: bind(\.weeklyReportAuto))
                    Picker("Stats digest", selection: Binding(
                        get: { settings.value?.statsDigestCadence ?? .off },
                        set: { settings.value?.statsDigestCadence = $0 }
                    )) {
                        Text("Off").tag(Cadence.off)
                        Text("Daily").tag(Cadence.daily)
                        Text("Weekly").tag(Cadence.weekly)
                        Text("Monthly").tag(Cadence.monthly)
                    }
                } header: {
                    Text("Written for you")
                }

                Section {
                    Toggle("Quiet hours", isOn: bind(\.quietHoursEnabled))
                    if value.quietHoursEnabled {
                        DatePicker("From", selection: time(\.quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: time(\.quietEnd), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Nothing is sent during quiet hours, in your account's time zone.")
                }

                WorkoutReminderSection()

                Section {
                    Toggle("Ask for progress photos", isOn: bind(\.photoAskEnabled))
                    if value.photoAskEnabled {
                        Stepper("Every \(value.photoEveryDays) days", value: int(\.photoEveryDays), in: 1...90)
                        Stepper("Remind after \(value.photoReminderDays) days", value: int(\.photoReminderDays), in: 0...30)
                    }
                }
                if let error = settings.error { ErrorRow(error) }
            }
        }
        .navigationTitle("Notifications")
        .saveToolbar(settings) { try await service.save($0) }
        .task { await settings.load(service.notifications) }
    }

    private func bind(_ keyPath: WritableKeyPath<SettingsModel.NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings.value?[keyPath: keyPath] ?? false }, set: { settings.value?[keyPath: keyPath] = $0 })
    }

    private func int(_ keyPath: WritableKeyPath<SettingsModel.NotificationSettings, Int>) -> Binding<Int> {
        Binding(get: { settings.value?[keyPath: keyPath] ?? 0 }, set: { settings.value?[keyPath: keyPath] = $0 })
    }

    /// "HH:MM" on the wire, a Date in the picker.
    private func time(_ keyPath: WritableKeyPath<SettingsModel.NotificationSettings, String>) -> Binding<Date> {
        Binding(
            get: { ClockTime.date(from: settings.value?[keyPath: keyPath] ?? "") },
            set: { settings.value?[keyPath: keyPath] = ClockTime.string(from: $0) }
        )
    }
}

/// "22:00" ↔ today at 22:00, for time pickers.
enum ClockTime {
    static func date(from string: String) -> Date {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        let components = DateComponents(hour: parts.first ?? 0, minute: parts.dropFirst().first ?? 0)
        return Calendar.current.date(from: components) ?? .now
    }

    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Shared pieces

struct ErrorRow: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
    }
}

extension View {
    /// A Save button that appears once there is something to save.
    func saveToolbar<Value: Equatable>(_ editable: Editable<Value>, send: @escaping (Value) async throws -> Value) -> some View {
        toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if editable.isSaving {
                    ProgressView()
                } else if editable.hasChanges {
                    Button("Save") { Task { await editable.save(send) } }
                }
            }
        }
    }
}

/// Workout reminders are scheduled by this iPhone from the plan's start
/// times, so their switch lives here rather than on the server.
private struct WorkoutReminderSection: View {
    @State private var enabled = WorkoutReminderSettings.enabled
    @State private var lead = WorkoutReminderSettings.leadMinutes

    var body: some View {
        Section {
            Toggle("Before each workout", isOn: $enabled)
            if enabled {
                Picker("Remind me", selection: $lead) {
                    Text("At the start time").tag(0)
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes before").tag($0) }
                }
            }
        } header: {
            Text("On this iPhone")
        } footer: {
            Text("From the start times on your training days. Scheduled on this iPhone, so they arrive even offline.")
        }
        .onChange(of: enabled) { _, on in
            WorkoutReminderSettings.enabled = on
            Task { await WorkoutReminderSettings.apply() }
        }
        .onChange(of: lead) { _, minutes in
            WorkoutReminderSettings.leadMinutes = minutes
            Task { await WorkoutReminderSettings.apply() }
        }
    }
}
