import SwiftUI
import UIKit

/// How the person wants the app drawn: following the phone, or always light
/// or dark.
///
/// The account keeps the choice so it follows the person to the web, and this
/// iPhone keeps a copy so a launch draws the right way before the network
/// answers. Widgets, the Live Activity, the share extension and the Screen
/// Time report are separate processes with no shared defaults, so they keep
/// following the phone.
enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    static let defaultsKey = "appearance"

    /// The account's value. Missing, or a value added after this build
    /// shipped, means following the phone.
    init(profileValue: String?) {
        self = profileValue.flatMap(Self.init(rawValue:)) ?? .system
    }

    var id: Self { self }

    /// The value the profile stores.
    var profileValue: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system:
            String(localized: "appearance.system", defaultValue: "System",
                   comment: "Appearance: follow the iPhone's light or dark setting")
        case .light: String(localized: "appearance.light", defaultValue: "Light", comment: "Appearance: always light")
        case .dark: String(localized: "appearance.dark", defaultValue: "Dark", comment: "Appearance: always dark")
        }
    }

    /// This iPhone's copy; following the phone until something is chosen.
    static func stored(in defaults: UserDefaults = .standard) -> Self {
        Self(profileValue: defaults.string(forKey: defaultsKey))
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    /// Draws every window of every scene this way. Sheets, full-screen covers
    /// and alerts are presented inside their window, so they follow it.
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != interfaceStyle {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}
