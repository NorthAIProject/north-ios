import Foundation
import NorthAPI
import NorthKit
import SwiftUI

/// Where a check-in was filed, as the history shows it.
///
/// The server sends `source` as an open string, so a value added later
/// (a watch, a new integration) still decodes; this build names the ones it
/// knows and calls the rest "Elsewhere".
enum CheckInSource {
    /// What this app sends when the person checks in here.
    static let app = "ios"
    /// What the Log Check-In shortcut sends.
    static let siri = "siri"

    static func label(_ source: String) -> String {
        switch source {
        case "ios": String(localized: "iPhone")
        case "web": String(localized: "Web")
        case "siri": String(localized: "Siri")
        case "coach": String(localized: "Coach")
        case "mcp": String(localized: "Agent")
        case "capture": String(localized: "Capture")
        default: String(localized: "Elsewhere")
        }
    }

    static func systemImage(_ source: String) -> String {
        switch source {
        case "ios": "iphone"
        case "web": "globe"
        case "siri": "waveform"
        case "coach": "bubble.left.and.text.bubble.right"
        case "mcp": "puzzlepiece.extension"
        case "capture": "camera"
        default: "questionmark.circle"
        }
    }
}

/// Tags as typed into one field: comma-separated, trimmed, without a leading
/// `#`, each kept once in the order written.
enum CheckInTags {
    static func parse(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func text(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }
}

extension CheckIn {
    /// Whether the check-in changed after it was filed. A save within the
    /// first minute is the same sitting, not an edit.
    var wasEdited: Bool {
        updatedAt.timeIntervalSince(createdAt) > 60
    }
}

/// A check-in's tags as small capsules that wrap onto more lines.
struct CheckInTagChips: View {
    let tags: [String]

    var body: some View {
        WrappingStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NorthColor.signal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NorthColor.signal.opacity(0.12), in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Tags: \(tags.joined(separator: ", "))"))
    }
}

/// Lays its children out left to right, starting a new line when the next
/// one does not fit.
private struct WrappingStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var left = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: left, y: top), proposal: ProposedViewSize(size))
                left += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
