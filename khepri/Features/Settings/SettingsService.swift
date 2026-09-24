import Foundation
import NorthAPI

/// The settings schemas, under one short name: several (`Preferences`,
/// `Profile`) are words the app would otherwise want for itself.
typealias SettingsModel = Components.Schemas

/// Settings, over the generated client. One call per card on the web page.
protocol SettingsServicing: Sendable {
    func profile() async throws -> SettingsModel.Profile
    func save(_ profile: SettingsModel.Profile) async throws -> SettingsModel.Profile
    func preferences() async throws -> SettingsModel.Preferences
    func save(_ preferences: SettingsModel.Preferences) async throws -> SettingsModel.Preferences
    func notifications() async throws -> SettingsModel.NotificationSettings
    func save(_ notifications: SettingsModel.NotificationSettings) async throws -> SettingsModel.NotificationSettings

    func ai() async throws -> SettingsModel.AISettings
    func saveAI(provider: String, apiKey: String, model: String, baseURL: String) async throws -> SettingsModel.AISettings
    func removeAI() async throws

    func connections() async throws -> SettingsModel.ConnectionList
    func createConnection(name: String, kind: SettingsModel.CreateConnectionRequest.KindPayload) async throws -> SettingsModel.CreatedConnection
    func revokeConnection(_ id: String) async throws
    func activity() async throws -> [SettingsModel.Execution]

    func telegram() async throws -> SettingsModel.TelegramSettings
    func telegramCode() async throws -> SettingsModel.TelegramCode
    func unlinkTelegram() async throws

    func calendar() async throws -> SettingsModel.CalendarSettings
    func connectCalendar(endpoint: String, token: String) async throws -> SettingsModel.CalendarSettings
    func disconnectCalendar() async throws

    func deleteAccount(confirmEmail: String) async throws
}

struct SettingsService: SettingsServicing {
    var api: Client = API.shared

    func profile() async throws -> SettingsModel.Profile {
        try await NorthAPI.call { try await api.getProfile().ok.body.json }
    }

    func save(_ profile: SettingsModel.Profile) async throws -> SettingsModel.Profile {
        try await NorthAPI.call { try await api.updateProfile(body: .json(profile)).ok.body.json }
    }

    func preferences() async throws -> SettingsModel.Preferences {
        try await NorthAPI.call { try await api.getPreferences().ok.body.json }
    }

    func save(_ preferences: SettingsModel.Preferences) async throws -> SettingsModel.Preferences {
        try await NorthAPI.call { try await api.updatePreferences(body: .json(preferences)).ok.body.json }
    }

    func notifications() async throws -> SettingsModel.NotificationSettings {
        try await NorthAPI.call { try await api.getNotificationSettings().ok.body.json }
    }

    func save(_ notifications: SettingsModel.NotificationSettings) async throws -> SettingsModel.NotificationSettings {
        try await NorthAPI.call { try await api.updateNotificationSettings(body: .json(notifications)).ok.body.json }
    }

    func ai() async throws -> SettingsModel.AISettings {
        try await NorthAPI.call { try await api.getAISettings().ok.body.json }
    }

    func saveAI(provider: String, apiKey: String, model: String, baseURL: String) async throws -> SettingsModel.AISettings {
        let request = SettingsModel.AIProviderRequest(
            provider: provider, apiKey: apiKey,
            model: model.isEmpty ? nil : model, baseUrl: baseURL.isEmpty ? nil : baseURL
        )
        return try await NorthAPI.call { try await api.saveAIProvider(body: .json(request)).ok.body.json }
    }

    func removeAI() async throws {
        _ = try await NorthAPI.call { try await api.removeAIProvider().noContent }
    }

    func connections() async throws -> SettingsModel.ConnectionList {
        try await NorthAPI.call { try await api.listConnections().ok.body.json }
    }

    func createConnection(name: String, kind: SettingsModel.CreateConnectionRequest.KindPayload) async throws -> SettingsModel.CreatedConnection {
        try await NorthAPI.call { try await api.createConnection(body: .json(.init(name: name, kind: kind))).created.body.json }
    }

    func revokeConnection(_ id: String) async throws {
        _ = try await NorthAPI.call { try await api.revokeConnection(path: .init(connectionID: id)).noContent }
    }

    func activity() async throws -> [SettingsModel.Execution] {
        try await NorthAPI.call { try await api.listActivity().ok.body.json.executions }
    }

    func telegram() async throws -> SettingsModel.TelegramSettings {
        try await NorthAPI.call { try await api.getTelegramSettings().ok.body.json }
    }

    func telegramCode() async throws -> SettingsModel.TelegramCode {
        try await NorthAPI.call { try await api.issueTelegramCode().created.body.json }
    }

    func unlinkTelegram() async throws {
        _ = try await NorthAPI.call { try await api.unlinkTelegram().noContent }
    }

    func calendar() async throws -> SettingsModel.CalendarSettings {
        try await NorthAPI.call { try await api.getCalendarSettings().ok.body.json }
    }

    func connectCalendar(endpoint: String, token: String) async throws -> SettingsModel.CalendarSettings {
        try await NorthAPI.call {
            try await api.connectCalendar(body: .json(.init(endpoint: endpoint, token: token.isEmpty ? nil : token))).ok.body.json
        }
    }

    func disconnectCalendar() async throws {
        _ = try await NorthAPI.call { try await api.disconnectCalendar().noContent }
    }

    func deleteAccount(confirmEmail: String) async throws {
        _ = try await NorthAPI.call { try await api.deleteAccount(body: .json(.init(confirmEmail: confirmEmail))).noContent }
    }
}
