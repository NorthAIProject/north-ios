import CoreText
import SwiftUI

/// Geist and Geist Mono, the web app's typefaces, bundled as variable TTFs.
///
/// Fonts inside a Swift package cannot be declared in the app's Info.plist, so
/// they are registered with Core Text at launch. Call `register()` once, before
/// the first view renders.
public enum NorthFont {
    static let sans = "Geist"
    static let mono = "Geist Mono"

    public static func register() {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil), !urls.isEmpty else {
            assertionFailure("NorthKit bundle has no fonts")
            return
        }
        // Errors here mean "already registered", which is harmless on relaunch
        // of a scene; the fonts are still available.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

#if canImport(UIKit)
import UIKit

public extension Font {
    /// Geist at the size of a system text style, so it follows Dynamic Type.
    static func north(_ style: Font.TextStyle) -> Font {
        .custom(NorthFont.sans, size: UIFontMetrics.defaultSize(for: style), relativeTo: style)
    }

    /// Geist at a fixed size that still scales with the given text style, for
    /// the rare figure larger than any text style.
    static func north(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(NorthFont.sans, size: size, relativeTo: style)
    }

    /// Geist Mono at the size of a system text style, for numbers and timers.
    static func northMono(_ style: Font.TextStyle) -> Font {
        .custom(NorthFont.mono, size: UIFontMetrics.defaultSize(for: style), relativeTo: style)
    }
}

private extension UIFontMetrics {
    /// Point size of a text style at the default content size category.
    static func defaultSize(for style: Font.TextStyle) -> CGFloat {
        UIFont.preferredFont(
            forTextStyle: style.uiKit,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
#endif
