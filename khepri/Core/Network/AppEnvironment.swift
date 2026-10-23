import Foundation

/// Values that differ between the Debug, Beta and Release builds.
///
/// Each build configuration sets `API_BASE_URL`; `Config/Info.plist` copies it
/// into the `NorthAPIBaseURL` key so it can be read at runtime.
public enum AppEnvironment {
    public static let apiBaseURL: URL = {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "NorthAPIBaseURL") as? String,
            let url = URL(string: raw),
            url.scheme != nil
        else {
            preconditionFailure("NorthAPIBaseURL missing from Info.plist; check API_BASE_URL in the build configuration")
        }
        return url
    }()

    /// The App Store's numeric ID for this app, or nil until it is listed.
    /// `Config/Info.plist` holds it under `AppStoreID`, empty for now.
    public static let appStoreID: String? = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String ?? ""
        return raw.isEmpty ? nil : raw
    }()

    /// The invite to Khepri's channel on the community Discord. The same in
    /// every build, so it is a constant rather than an `Info.plist` key.
    public static let discordURL = URL(string: "https://discord.gg/FHHhFUk9e")!
}
