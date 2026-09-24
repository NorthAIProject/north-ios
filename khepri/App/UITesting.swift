import Foundation

/// Whether this launch is driven by the UI tests (`-uitest-reset`).
///
/// Used for one thing: iOS offers to save a password whenever a field marked
/// as a password is submitted, as a system prompt the tests cannot reliably
/// see or dismiss. Under test the auth fields drop their content type, so the
/// prompt never appears. Always false in Beta and Release builds.
enum UITesting {
    static let isActive: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-reset")
        #else
        false
        #endif
    }()
}
