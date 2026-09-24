import AuthenticationServices
import HealthKit
import NorthAPI
import SwiftUI

typealias StravaStatus = Components.Schemas.StravaStatus

protocol StravaServicing: Sendable {
    func status() async throws -> StravaStatus
    func authorizeURL() async throws -> URL
    func sync() async throws
    func disconnect() async throws
}

struct StravaService: StravaServicing {
    var api: Client = API.shared

    func status() async throws -> StravaStatus {
        try await NorthAPI.call { try await api.getStravaStatus().ok.body.json }
    }

    func authorizeURL() async throws -> URL {
        let raw = try await NorthAPI.call { try await api.connectStrava().ok.body.json.authorizeUrl }
        guard let url = URL(string: raw) else { throw APIError.invalidResponse }
        return url
    }

    func sync() async throws {
        try await NorthAPI.call { _ = try await api.syncStrava().accepted }
    }

    func disconnect() async throws {
        try await NorthAPI.call { _ = try await api.disconnectStrava().noContent }
    }
}

/// What the server's Strava callback says happened, read from
/// khepri://fitness/strava?result=…
enum StravaConnectResult: Equatable {
    case connected, cancelled, expired, failed

    init(callback: URL) {
        let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "result" }?.value
        switch result {
        case "connected": self = .connected
        case "cancelled": self = .cancelled
        case "expired": self = .expired
        default: self = .failed
        }
    }

    var message: String? {
        switch self {
        case .connected: nil
        case .cancelled: "Strava was not connected."
        case .expired: "That took too long. Try connecting again."
        case .failed: "Strava did not connect. Try again in a moment."
        }
    }
}

/// Strava: connect through Strava's own sign-in, then sync and status.
struct StravaSettings: View {
    var service: StravaServicing = StravaService()
    @State private var status: StravaStatus?
    @State private var error: String?
    @State private var working = false
    @State private var confirmingDisconnect = false
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Form {
            if let status {
                if !status.configured {
                    Text("Strava is not set up on this server.").foregroundStyle(.secondary)
                } else if status.connected {
                    Section {
                        LabeledContent("Status", value: status.syncPending ? "Syncing…" : "Connected")
                        if let synced = status.lastSyncedAt {
                            LabeledContent("Last sync", value: synced.formatted(.relative(presentation: .named)))
                        }
                        if let failure = status.lastSyncError, !failure.isEmpty {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Activities import every few hours. A run that Apple Health also recorded is counted once.")
                    }
                    Button("Sync Now") { Task { await run { try await service.sync() } } }
                        .disabled(working || status.syncPending)
                    Button("Disconnect Strava", role: .destructive) { confirmingDisconnect = true }
                } else {
                    Section {
                        Button("Connect Strava") { Task { await connect() } }
                            .disabled(working)
                    } footer: {
                        Text("Opens Strava to sign in. Your runs and rides then reach your coach and your progress.")
                    }
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Strava")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Disconnect Strava?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await run { try await service.disconnect() } } }
        } message: {
            Text("Activities already imported stay in your history.")
        }
    }

    private func load() async {
        do { status = try await service.status(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func run(_ action: () async throws -> Void) async {
        working = true
        defer { working = false }
        do { try await action(); await load() } catch { self.error = error.localizedDescription }
    }

    private func connect() async {
        working = true
        defer { working = false }
        do {
            let url = try await service.authorizeURL()
            let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: "khepri")
            error = StravaConnectResult(callback: callback).message
            await load()
        } catch let authError as ASWebAuthenticationSessionError where authError.code == .canceledLogin {
            // Closing the sheet is an answer, not an error.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Apple Health: whether it syncs, when it last did, and a way to stop.
struct HealthSettings: View {
    @State private var enabled = HealthSync.shared.isEnabled
    @State private var report = HealthSync.shared.lastReport
    @State private var working = false
    @State private var error: String?
    @State private var confirmingStop = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            if !HKHealthStore.isHealthDataAvailable() {
                Text("Apple Health is not available on this device.").foregroundStyle(.secondary)
            } else {
                Section {
                    Toggle("Sync Apple Health", isOn: Binding(
                        get: { enabled },
                        set: { on in
                            if on {
                                Task { await turnOn() }
                            } else {
                                confirmingStop = true
                            }
                        }
                    ))
                    .disabled(working)
                    if enabled {
                        if let report {
                            LabeledContent("Last sync", value: report.at.formatted(.relative(presentation: .named)))
                        }
                        Button("Sync Now") { Task { await syncNow() } }
                            .disabled(working)
                    }
                } footer: {
                    Text("Workouts, steps, active energy, resting heart rate, HRV and sleep. Your coach sees them beside what you tell it. Workouts you finish in Khepri are saved to Apple Health.")
                }
                Section {
                    Button("Choose What Khepri Reads") {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    }
                } footer: {
                    Text("In the Health app: Sharing → Apps → Khepri.")
                }
            }
            if working { ProgressView() }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Apple Health")
        .confirmationDialog("Stop syncing Apple Health?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Syncing") {
                HealthSync.shared.setEnabled(false)
                enabled = false
            }
            Button("Stop and Delete Synced Data", role: .destructive) { Task { await disconnect() } }
        } message: {
            Text("Deleting removes the heart rate, sleep and step readings Khepri received. Workouts stay in your activity history.")
        }
    }

    private func turnOn() async {
        working = true
        defer { working = false }
        await Permissions.requestHealth()
        HealthSync.shared.setEnabled(true)
        enabled = true
        HealthBackgroundDelivery.register()
        await syncNow()
    }

    private func syncNow() async {
        working = true
        defer { working = false }
        do {
            report = try await HealthSync.shared.syncIfEnabled() ?? report
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func disconnect() async {
        working = true
        defer { working = false }
        do {
            try await HealthSync.shared.disconnect()
            enabled = false
            report = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
