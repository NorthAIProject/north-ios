#if canImport(UIKit)
import SwiftUI
import UIKit

public extension View {
    /// The large rounded card most screens are built from: generous padding,
    /// the grouped background and a hairline edge that holds it apart from
    /// the page in dark mode.
    func northSurfaceCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: NorthRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NorthRadius.large, style: .continuous)
                    .strokeBorder(NorthColor.hairline.opacity(0.6), lineWidth: 0.5)
            }
    }
}

/// A card's eyebrow with an optional action or accessory on the right:
/// "WEIGHT … Log weight", "RECENT … See all".
public struct NorthCardHeader<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    public init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text(title).northEyebrow()
                if let detail {
                    Text("·").foregroundStyle(.tertiary)
                    Text(detail).font(.north(.subheadline)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            trailing
                .font(.north(.subheadline))
        }
        .accessibilityElement(children: .contain)
    }
}

public extension NorthCardHeader where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

/// The number a card is about, with its unit small beside it: "6.5k steps",
/// "41.9 ml/kg/min".
public struct NorthBigValue: View {
    let value: String
    let unit: String?
    let style: Font.TextStyle

    public init(_ value: String, unit: String? = nil, style: Font.TextStyle = .largeTitle) {
        self.value = value
        self.unit = unit
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.north(style).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.north(.title3))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rows grouped on a darker inset inside a card, divided by hairlines that
/// start at the text.
public struct NorthInsetList<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let row: (Data.Element) -> Row

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.id = id
        self.row = row
    }

    public var body: some View {
        VStack(spacing: 0) {
            let first = data.first.map { $0[keyPath: id] }
            ForEach(data, id: id) { element in
                if element[keyPath: id] != first {
                    Divider().padding(.leading, 16)
                }
                row(element)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.systemBackground).opacity(0.55), in: .rect(cornerRadius: NorthRadius.medium + 2, style: .continuous))
    }
}
#endif
