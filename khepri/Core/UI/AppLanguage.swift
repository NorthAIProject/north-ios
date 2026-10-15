import Foundation

/// The language the app's own screens are in.
///
/// iOS reads it once, at launch, from the per-app `AppleLanguages` default:
/// the same value Settings → Khepri → Language writes. Changing it here takes
/// effect the next time the app opens; the coach, reports and reminders follow
/// the account's locale on the server and switch at once.
enum AppLanguage {
    /// The account's languages, each named in itself. The two Portugueses stay
    /// apart, as they do on the web.
    static let all: [(tag: String, name: String)] = [
        ("en", "English"), ("pt-PT", "Português (Portugal)"), ("pt-BR", "Português (Brasil)"), ("es", "Español"),
    ]

    static let defaultsKey = "AppleLanguages"

    /// The language this launch is showing.
    static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Makes the next launch use `tag`. Tags the app has no translation for
    /// are ignored rather than sending iOS somewhere unexpected.
    static func apply(_ tag: String, defaults: UserDefaults = .standard) {
        guard all.contains(where: { $0.tag == tag }) else { return }
        // Always written, never compared first: reading the key falls through
        // to the phone's own language list, which is not the app's choice.
        defaults.set([tag], forKey: defaultsKey)
    }

    /// Whether `tag` will only show after the app is opened again.
    static func needsRelaunch(for tag: String) -> Bool {
        tag != current
    }
}
