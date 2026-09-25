import NorthAPI
import NorthKit
import SwiftUI

/// Recent timed and logged sessions, and a way to record one after the fact.
struct ActivityHistoryScreen: View {
    var service: ActivityServicing = ActivityService()

    @State private var overview: Components.Schemas.ActivityOverview?
    @State private var error: String?
    @State private var logging = false

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let overview {
                if overview.recent.isEmpty {
                    Section {
                        Text("Nothing yet. Workouts you time, and anything you log here, show up in this list.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Recent") {
                        ForEach(overview.recent, id: \.id) { SessionRow(session: $0) }
                    }
                }
            } else if error == nil {
                ProgressView()
            }
        }
        .navigationTitle("Activity History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Log Activity", systemImage: "plus") { logging = true }
                    .disabled(overview == nil)
            }
        }
        .sheet(isPresented: $logging) {
            if let kinds = overview?.kinds {
                LogActivitySheet(kinds: kinds, service: service) { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            overview = try await service.overview()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct SessionRow: View {
    let session: ActivitySession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.activityName)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Duration.seconds(session.elapsedSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    .font(.subheadline.monospacedDigit())
                if let kcal = session.caloriesBurned {
                    Text("\(Int(kcal.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The web's "log after the fact" form: what, when, how long, how far.
private struct LogActivitySheet: View {
    let kinds: [Components.Schemas.ActivityKind]
    let service: ActivityServicing
    let onLogged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var startedAt = Date.now.addingTimeInterval(-3600)
    @State private var minutes = 30
    @State private var distance = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $code) {
                        Text("Choose…").tag("")
                        ForEach(categories, id: \.self) { category in
                            Section(category.capitalized) {
                                ForEach(kinds.filter { $0.category == category }, id: \.code) { kind in
                                    Text(kind.name).tag(kind.code)
                                }
                            }
                        }
                    }
                    DatePicker("Started", selection: $startedAt, in: ...Date.now)
                    Stepper("\(minutes) min", value: $minutes, in: 1...600, step: 5)
                    TextField("Distance (km, optional)", text: $distance)
                        .keyboardType(.decimalPad)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("Log Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(code.isEmpty || parsedDistance == .invalid)
                    }
                }
            }
        }
    }

    private var categories: [String] {
        var seen: [String] = []
        for kind in kinds where !seen.contains(kind.category) { seen.append(kind.category) }
        return seen
    }

    private enum ParsedDistance: Equatable { case none, km(Double), invalid }

    private var parsedDistance: ParsedDistance {
        let trimmed = distance.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .none }
        guard let km = Double(trimmed.replacingOccurrences(of: ",", with: ".")), km > 0 else { return .invalid }
        return .km(km)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var km: Double?
        if case .km(let value) = parsedDistance { km = value }
        do {
            _ = try await service.log(.init(activityCode: code, startedAt: startedAt, durationMinutes: minutes, distanceKm: km))
            await onLogged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
