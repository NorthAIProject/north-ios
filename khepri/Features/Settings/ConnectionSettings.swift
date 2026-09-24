import NorthAPI
import NorthKit
import SwiftUI

// MARK: - AI provider

/// Bring your own key, or use Khepri's providers.
struct AIProviderSettings: View {
    let service: SettingsServicing
    @State private var settings: SettingsModel.AISettings?
    @State private var error: String?
    @State private var editing = false

    var body: some View {
        Form {
            if let settings {
                if !settings.enabled {
                    Text("This server cannot store provider keys.")
                        .foregroundStyle(.secondary)
                } else if let current = settings.current {
                    Section {
                        LabeledContent("Provider", value: label(current.provider, in: settings))
                        LabeledContent("Key", value: current.keyHint)
                        if let model = current.model { LabeledContent("Model", value: model) }
                        LabeledContent("Coach tools") {
                            switch current.supportsTools {
                            case true?: Text("Supported")
                            case false?: Text("Not supported").foregroundStyle(.orange)
                            case nil: Text("Checking…").foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("If this provider refuses or runs out of credit, Khepri's providers answer instead, so the coach never goes silent.")
                    }
                    if let lastError = current.lastError {
                        Section("Last problem") { Text(lastError).foregroundStyle(.secondary) }
                    }
                    Section {
                        Button("Change Key") { editing = true }
                        Button("Use Khepri's Providers", role: .destructive) {
                            Task {
                                do {
                                    try await service.removeAI()
                                    await load()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Your coach runs on Khepri's providers.")
                        Button("Use My Own Key") { editing = true }
                    } footer: {
                        Text("Bring a key from a provider you already pay for. It is stored encrypted and never shown again.")
                    }
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("AI Provider")
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let settings {
                AIKeySheet(settings: settings, service: service) { updated in
                    self.settings = updated
                }
            }
        }
    }

    private func load() async {
        do { settings = try await service.ai(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func label(_ name: String, in settings: SettingsModel.AISettings) -> String {
        settings.providers.first { $0.name == name }?.label ?? name
    }
}

private struct AIKeySheet: View {
    let settings: SettingsModel.AISettings
    let service: SettingsServicing
    let onSaved: (SettingsModel.AISettings) -> Void

    @State private var provider = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var baseURL = ""
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var chosen: SettingsModel.AIProvider? { settings.providers.first { $0.name == provider } }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(settings.providers, id: \.name) { Text($0.label).tag($0.name) }
                }
                Section {
                    SecureField(chosen?.keyHint ?? "API key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(chosen?.defaultModel ?? "Model (optional)", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(chosen?.baseUrl ?? "Base URL (optional)", text: $baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("Your Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(provider.isEmpty || apiKey.isEmpty)
                    }
                }
            }
            .onAppear {
                provider = settings.current?.provider ?? settings.providers.first?.name ?? ""
                model = settings.current?.model ?? ""
                baseURL = settings.current?.baseUrl ?? ""
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            onSaved(try await service.saveAI(provider: provider, apiKey: apiKey, model: model, baseURL: baseURL))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Agents (MCP)

/// Agents like Claude Code and Codex reaching this account over MCP.
struct AgentConnections: View {
    let service: SettingsServicing
    @State private var list: SettingsModel.ConnectionList?
    @State private var error: String?
    @State private var adding = false
    @State private var created: SettingsModel.CreatedConnection?

    var body: some View {
        Form {
            if let list {
                Section {
                    if list.connections.isEmpty {
                        Text("No agents connected.").foregroundStyle(.secondary)
                    }
                    ForEach(list.connections, id: \.id) { connection in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.name)
                            Text(detail(connection)).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Revoke", role: .destructive) { Task { await revoke(connection) } }
                        }
                    }
                } footer: {
                    Text("Agents act on your behalf with the same tools the coach has. Revoke one to cut it off at once.")
                }
                Section {
                    Button("Connect an Agent", systemImage: "plus") { adding = true }
                    NavigationLink("Activity") { ActivityList(service: service) }
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Agents")
        .task { await load() }
        .sheet(isPresented: $adding) {
            NewConnectionSheet(service: service) { issued in
                created = issued
                Task { await load() }
            }
        }
        .sheet(item: Binding(get: { created.map(CreatedToken.init) }, set: { if $0 == nil { created = nil } })) { token in
            TokenSheet(created: token.value)
        }
    }

    private func detail(_ connection: SettingsModel.Connection) -> String {
        let kind = connection.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        guard let used = connection.lastUsedAt else { return "\(kind) · never used" }
        return "\(kind) · used \(used.formatted(.relative(presentation: .named)))"
    }

    private func load() async {
        do { list = try await service.connections(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func revoke(_ connection: SettingsModel.Connection) async {
        do {
            try await service.revokeConnection(connection.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CreatedToken: Identifiable {
    let value: SettingsModel.CreatedConnection
    var id: String { value.connection.id }
}

private struct NewConnectionSheet: View {
    let service: SettingsServicing
    let onCreated: (SettingsModel.CreatedConnection) -> Void
    @State private var name = ""
    @State private var kind: SettingsModel.CreateConnectionRequest.KindPayload = .claudeCode
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Work laptop", text: $name)
                Picker("Agent", selection: $kind) {
                    Text("Claude Code").tag(SettingsModel.CreateConnectionRequest.KindPayload.claudeCode)
                    Text("Codex").tag(SettingsModel.CreateConnectionRequest.KindPayload.codex)
                    Text("Hermes").tag(SettingsModel.CreateConnectionRequest.KindPayload.hermes)
                    Text("Other").tag(SettingsModel.CreateConnectionRequest.KindPayload.other)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("Connect an Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            do {
                                let created = try await service.createConnection(name: name, kind: kind)
                                dismiss()
                                onCreated(created)
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// The only time the token is visible. Copy it now.
private struct TokenSheet: View {
    let created: SettingsModel.CreatedConnection
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(created.token)
                        .font(.northMono(.footnote))
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy Token", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = created.token
                        copied = true
                    }
                } header: {
                    Text("Token")
                } footer: {
                    Text("Shown once. If you lose it, revoke this connection and create another.")
                }
                if let config = created.setup.config {
                    Section((created.setup.configLabel ?? "Setup").localizedCapitalized) {
                        Text(config)
                            .font(.northMono(.caption))
                            .textSelection(.enabled)
                    }
                }
                Section("MCP endpoint") {
                    Text(created.setup.url).textSelection(.enabled)
                }
            }
            .navigationTitle(created.connection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .interactiveDismissDisabled(!copied)
        }
    }
}

private struct ActivityList: View {
    let service: SettingsServicing
    @State private var executions: [SettingsModel.Execution]?
    @State private var error: String?

    var body: some View {
        List {
            if let executions {
                if executions.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(executions, id: \.id) { execution in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(execution.tool.replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            Text(execution.outcome.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(execution.outcome == .executed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        }
                        Text("\(execution.surface == "mcp" ? "Agent" : "Coach") · \(execution.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error {
                ErrorRow(error)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Activity")
        .task {
            do { executions = try await service.activity() } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Telegram

struct TelegramSettings: View {
    let service: SettingsServicing
    @State private var settings: SettingsModel.TelegramSettings?
    @State private var code: SettingsModel.TelegramCode?
    @State private var error: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            if let settings {
                if !settings.enabled {
                    Text("Telegram is not set up on this server.").foregroundStyle(.secondary)
                } else if settings.linked {
                    Section {
                        LabeledContent("Status", value: "Linked")
                        if let bot = settings.botUsername { LabeledContent("Bot", value: "@\(bot)") }
                        if let seen = settings.lastSeenAt {
                            LabeledContent("Last message", value: seen.formatted(.relative(presentation: .named)))
                        }
                    } footer: {
                        Text("The same coach, the same memory: what you say there appears here.")
                    }
                    Button("Disconnect Telegram", role: .destructive) {
                        Task {
                            do { try await service.unlinkTelegram(); await load() } catch { self.error = error.localizedDescription }
                        }
                    }
                } else {
                    Section {
                        Button("Link Telegram") { Task { await link() } }
                        if let code {
                            LabeledContent("Code", value: code.code)
                                .textSelection(.enabled)
                        }
                    } footer: {
                        if let code, code.deepLink == nil {
                            Text("Send /start \(code.code) to the bot.")
                        } else {
                            Text("Opens Telegram with a one-time code. Come back here once the bot says hello.")
                        }
                    }
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Telegram")
        .task { await load() }
        // Back from Telegram: the link has probably just happened.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func load() async {
        do { settings = try await service.telegram(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func link() async {
        do {
            let issued = try await service.telegramCode()
            code = issued
            if let link = issued.deepLink.flatMap(URL.init(string:)) { openURL(link) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Calendar

struct CalendarSettings: View {
    let service: SettingsServicing
    @State private var settings: SettingsModel.CalendarSettings?
    @State private var endpoint = ""
    @State private var token = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            if let settings {
                if !settings.enabled {
                    Text("Calendars are not available on this server.").foregroundStyle(.secondary)
                } else if let connected = settings.connected {
                    Section {
                        LabeledContent("Server", value: connected.endpoint)
                        LabeledContent("Status", value: connected.status.capitalized)
                        if let problem = connected.lastError { Text(problem).foregroundStyle(.secondary) }
                    } footer: {
                        Text("Your coach reads upcoming events to plan around them.")
                    }
                    Button("Disconnect Calendar", role: .destructive) {
                        Task {
                            do { try await service.disconnectCalendar(); await load() } catch { self.error = error.localizedDescription }
                        }
                    }
                } else {
                    Section {
                        TextField("MCP server URL", text: $endpoint)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Token (if the server needs one)", text: $token)
                    } footer: {
                        Text("A calendar you run behind an MCP server. Khepri reads it; it never writes to it.")
                    }
                    Button(working ? "Connecting…" : "Connect") { Task { await connect() } }
                        .disabled(endpoint.isEmpty || working)
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Calendar")
        .task { await load() }
    }

    private func load() async {
        do { settings = try await service.calendar(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func connect() async {
        working = true
        defer { working = false }
        do {
            settings = try await service.connectCalendar(endpoint: endpoint, token: token)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Delete account

/// Deleting is typed, not tapped: the account's email is the confirmation.
struct DeleteAccountSheet: View {
    let email: String
    let service: SettingsServicing
    let onDeleted: () -> Void
    @State private var typed = ""
    @State private var error: String?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This erases your goals, check-ins, conversations, memories and everything else, on every device. It cannot be undone.")
                }
                Section {
                    TextField(email, text: $typed)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Type your email to confirm")
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        Task {
                            working = true
                            defer { working = false }
                            do {
                                try await service.deleteAccount(confirmEmail: typed)
                                dismiss()
                                onDeleted()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(typed.caseInsensitiveCompare(email) != .orderedSame || working)
                }
            }
        }
    }
}
