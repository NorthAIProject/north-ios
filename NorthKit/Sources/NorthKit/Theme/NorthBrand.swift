import SwiftUI

/// Brand artwork shared by the app and its extensions.
public enum NorthBrand {
    /// The scarab and sun, gold on transparent, as a vector PDF traced from
    /// the web app's emblem. It carries fixed brand colour on both themes, as
    /// on the web; never tint it.
    public static let mark = Image("KhepriMark", bundle: .module)

    public static let name = "Khepri"
    public static let tagline = "Your AI operating system for personal growth."
}
