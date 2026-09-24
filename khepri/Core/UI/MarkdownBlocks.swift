import SwiftUI

/// Markdown with structure: headings, lists and paragraphs, for the coach's
/// reports. Chat uses inline Markdown only; a weekly report is a document.
///
/// Deliberately small. It reads the few block forms the coach writes and
/// hands each block's text to the inline renderer; anything else is shown as
/// a paragraph rather than dropped.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(number: String, text: String)
    case paragraph(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"),
                      line[hashes] == " ", line.distance(from: line.startIndex, to: hashes) <= 6 {
                flush()
                blocks.append(.heading(level: line.distance(from: line.startIndex, to: hashes),
                                       text: String(line[hashes...]).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.numbered(number: String(line[..<dot]), text: String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }
}

struct MarkdownBlocksView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(Markdown.render(text))
                        .font(level <= 2 ? .title3.weight(.semibold) : .headline)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(Markdown.render(text))
                    }
                case .numbered(let number, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                        Text(Markdown.render(text))
                    }
                case .paragraph(let text):
                    Text(Markdown.render(text))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
