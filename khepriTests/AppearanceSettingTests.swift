import Foundation
import NorthAPI
import SwiftUI
import Testing
import UIKit
@testable import khepri

struct AppearanceSettingTests {
    @Test func readsEachValueTheProfileStores() {
        #expect(AppearanceSetting(profileValue: "system") == .system)
        #expect(AppearanceSetting(profileValue: "light") == .light)
        #expect(AppearanceSetting(profileValue: "dark") == .dark)
    }

    @Test func noValueFollowsThePhone() {
        #expect(AppearanceSetting(profileValue: nil) == .system)
    }

    @Test func aValueFromANewerServerFollowsThePhone() {
        #expect(AppearanceSetting(profileValue: "sepia") == .system)
        #expect(AppearanceSetting(profileValue: "Dark") == .system)
        #expect(AppearanceSetting(profileValue: "") == .system)
    }

    @Test func mapsToUIKitAndSwiftUI() {
        #expect(AppearanceSetting.system.interfaceStyle == .unspecified)
        #expect(AppearanceSetting.light.interfaceStyle == .light)
        #expect(AppearanceSetting.dark.interfaceStyle == .dark)
        #expect(AppearanceSetting.system.colorScheme == nil)
        #expect(AppearanceSetting.light.colorScheme == .light)
        #expect(AppearanceSetting.dark.colorScheme == .dark)
    }

    @Test func thisIPhonesCopyStartsAtSystemAndKeepsAChoice() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppearanceSettingTests.\(UUID().uuidString)"))
        #expect(AppearanceSetting.stored(in: defaults) == .system)
        AppearanceSetting.dark.store(in: defaults)
        #expect(defaults.string(forKey: "appearance") == "dark")
        #expect(AppearanceSetting.stored(in: defaults) == .dark)
    }
}

/// Where the choice is kept and when it reaches the account.
@MainActor
struct AppModelAppearanceTests {
    @Test func signedOutAChoiceStaysOnThisIPhone() async throws {
        let (model, settings, defaults) = try await makeModel(signedIn: false)
        await model.start()
        #expect(model.phase == .signedOut)

        model.chooseAppearance(.dark)
        try await model.saveAppearanceToAccount()

        #expect(model.appearance == .dark)
        #expect(AppearanceSetting.stored(in: defaults) == .dark)
        #expect(settings.savedAppearances.isEmpty)
    }

    @Test func signedInAChoiceIsSavedToTheAccount() async throws {
        let (model, settings, _) = try await makeModel(signedIn: true)
        await model.start()
        #expect(model.phase != .signedOut)

        model.chooseAppearance(.light)
        try await model.saveAppearanceToAccount()

        #expect(settings.savedAppearances == [.light])
    }

    @Test func theAccountsChoiceReplacesThisIPhones() async throws {
        let (model, settings, defaults) = try await makeModel(signedIn: false, stored: .light)
        #expect(model.appearance == .light)

        settings.profileAppearance = "dark"
        await model.syncFromAccount()

        #expect(model.appearance == .dark)
        #expect(AppearanceSetting.stored(in: defaults) == .dark)
    }

    @Test func anAccountThatNeverChoseKeepsThisIPhonesChoice() async throws {
        let (model, settings, defaults) = try await makeModel(signedIn: false)
        model.chooseAppearance(.dark)

        settings.profileAppearance = nil
        await model.syncFromAccount()

        #expect(model.appearance == .dark)
        #expect(AppearanceSetting.stored(in: defaults) == .dark)
    }

    @Test func aChoiceThatFailedToSaveIsSentAtTheNextSync() async throws {
        let (model, settings, defaults) = try await makeModel(signedIn: true)
        await model.start()
        settings.failSaves = true
        model.chooseAppearance(.dark)
        await #expect(throws: FakeProfileSettings.Offline.self) { try await model.saveAppearanceToAccount() }
        #expect(defaults.bool(forKey: AppModel.appearancePendingKey))

        settings.failSaves = false
        settings.profileAppearance = "light"
        await model.syncFromAccount()

        #expect(model.appearance == .dark)
        #expect(settings.savedAppearances.last == .dark)
        #expect(!defaults.bool(forKey: AppModel.appearancePendingKey))
    }

    @Test func quickChoicesLeaveTheLastOneOnTheAccount() async throws {
        let (model, settings, _) = try await makeModel(signedIn: true)
        await model.start()
        model.chooseAppearance(.dark)
        async let first: Void = model.saveAppearanceToAccount()
        model.chooseAppearance(.light)
        async let second: Void = model.saveAppearanceToAccount()
        _ = try await (first, second)

        #expect(settings.savedAppearances.last == .light)
    }

    private func makeModel(signedIn: Bool, stored: AppearanceSetting? = nil)
        async throws -> (AppModel, FakeProfileSettings, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "AppModelAppearanceTests.\(UUID().uuidString)"))
        stored?.store(in: defaults)
        let sessions = AuthSessionManager(secureStore: MemoryStore())
        if signedIn { try await sessions.storeSession(token: "kept", user: nil, expiresAt: nil) }
        let settings = FakeProfileSettings()
        let model = AppModel(auth: FakeAuth(), sessions: sessions,
                             notifications: NotificationCenter(), settings: settings, defaults: defaults)
        return (model, settings, defaults)
    }
}

/// The profile and the appearance save; nothing else in Settings is used.
final class FakeProfileSettings: SettingsServicing, @unchecked Sendable {
    var profileAppearance: String?
    private(set) var savedAppearances: [AppearanceSetting] = []

    struct Unused: Error {}

    func profile() async throws -> SettingsModel.Profile {
        var json: [String: Any] = [
            "email": "ana@example.com", "displayName": "Ana", "timezone": "Europe/Lisbon",
            "locale": "en", "coachingStyle": "", "coachingTone": "direct"
        ]
        json["appearance"] = profileAppearance
        return try JSONDecoder().decode(SettingsModel.Profile.self, from: JSONSerialization.data(withJSONObject: json))
    }

    var failSaves = false
    struct Offline: Error {}

    func saveAppearance(_ appearance: AppearanceSetting) async throws {
        if failSaves { throw Offline() }
        savedAppearances.append(appearance)
    }

    func save(_ profile: SettingsModel.Profile) async throws -> SettingsModel.Profile { throw Unused() }
    func preferences() async throws -> SettingsModel.Preferences { throw Unused() }
    func save(_ preferences: SettingsModel.Preferences) async throws -> SettingsModel.Preferences { throw Unused() }
    func notifications() async throws -> SettingsModel.NotificationSettings { throw Unused() }
    func save(_ notifications: SettingsModel.NotificationSettings) async throws -> SettingsModel.NotificationSettings {
        throw Unused()
    }
    func ai() async throws -> SettingsModel.AISettings { throw Unused() }
    func saveAI(provider: String, apiKey: String, model: String, baseURL: String)
        async throws -> SettingsModel.AISettings {
        throw Unused()
    }
    func removeAI() async throws { throw Unused() }
    func connections() async throws -> SettingsModel.ConnectionList { throw Unused() }
    func createConnection(name: String, kind: SettingsModel.CreateConnectionRequest.KindPayload)
        async throws -> SettingsModel.CreatedConnection {
        throw Unused()
    }
    func revokeConnection(_ id: String) async throws { throw Unused() }
    func activity() async throws -> [SettingsModel.Execution] { throw Unused() }
    func telegram() async throws -> SettingsModel.TelegramSettings { throw Unused() }
    func telegramCode() async throws -> SettingsModel.TelegramCode { throw Unused() }
    func unlinkTelegram() async throws { throw Unused() }
    func diets() async throws -> SettingsModel.DietSettings { throw Unused() }
    func saveDiets(_ ids: [String]) async throws -> SettingsModel.DietSettings { throw Unused() }
    func calendar() async throws -> SettingsModel.CalendarSettings { throw Unused() }
    func connectCalendar(endpoint: String, token: String) async throws -> SettingsModel.CalendarSettings {
        throw Unused()
    }
    func disconnectCalendar() async throws { throw Unused() }
    func deleteAccount(confirmEmail: String) async throws { throw Unused() }
}
