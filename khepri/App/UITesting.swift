import Foundation

/// Whether this launch is driven by the UI tests. Always false in Beta and
/// Release builds.
enum UITesting {
    /// A clean-install launch (`-uitest-reset`).
    ///
    /// iOS offers to save a password whenever a field marked as a password is
    /// submitted, as a system prompt the tests cannot reliably see or dismiss.
    /// Under test the auth fields drop their content type, so the prompt never
    /// appears.
    static let isActive: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-reset")
        #else
        false
        #endif
    }()

    /// Any launch by the UI tests, including a relaunch that keeps the install
    /// (`-uitest-skip-tour` without `-uitest-reset`). The App Store rating
    /// prompt stays away, since debug builds always show it.
    static let isLaunchedByTests: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uitest-") }
        #else
        false
        #endif
    }()
}
