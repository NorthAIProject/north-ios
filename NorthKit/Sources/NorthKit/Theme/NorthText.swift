#if canImport(UIKit)
import SwiftUI
import UIKit

public extension View {
    /// The small uppercase label above a value, a card or a group: Geist,
    /// tracked, quiet unless given a colour.
    func northEyebrow<S: ShapeStyle>(_ style: S = HierarchicalShapeStyle.secondary) -> some View {
        font(.north(.caption).weight(.medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(style)
    }

    /// A number that is the point of its view: Geist, light, with tabular
    /// digits, following Dynamic Type, and rolling when it changes. Not Geist
    /// Mono: its slashed zero reads as "Ø" at this size.
    func northDisplayNumber(_ style: Font.TextStyle) -> some View {
        font(.north(style).weight(.light))
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    /// The one prominent button on a screen. The accent is light in dark
    /// mode, where the system's white label all but disappears on it.
    func northProminentButton() -> some View {
        buttonStyle(.borderedProminent)
            .foregroundStyle(NorthColor.primaryForeground)
    }

    /// Padding and the grouped background of a standalone card.
    func northCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: NorthRadius.medium))
    }
}
#endif
