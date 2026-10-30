import SwiftUI

/// Brand artwork shared by the app and its extensions.
public enum NorthBrand {
    /// The solar emblem — gold-rimmed navy wings around a gold sphere — as a
    /// vector PDF rendered from north-web-app's scripts/brand/build.py, with a
    /// light and a dark appearance. Fixed brand colour; never tint it. For
    /// 48 pt and up.
    public static let mark = Image("KhepriMark", bundle: .module)

    /// The emblem's silhouette cut for 32 pt and below, where the detailed
    /// mark's hairline contours vanish: gold wings on dark, navy on light.
    public static let markSmall = Image("KhepriMarkSmall", bundle: .module)

    public static let name = "Khepri"
    public static let tagline = "Your AI operating system for personal growth."
}
