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
}
