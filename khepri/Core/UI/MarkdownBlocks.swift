import NorthKit
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

/// A report split the way it is read: the opening the coach leads with, then
/// one section per heading.
///
/// Grouping goes by position, never by heading text: reports are written in
/// the reader's language, so "What moved" may arrive as "O que avançou".
struct MarkdownDocument: Equatable {
    struct Section: Equatable {
        var heading: String?
        var blocks: [MarkdownBlock]
    }

    var lead: [MarkdownBlock] = []
    var sections: [Section] = []

    /// A leading level-1 heading is the report's title, which the screen
    /// already shows above the body, so it is dropped.
    init(_ blocks: [MarkdownBlock]) {
        var blocks = blocks[...]
        if case .heading(1, _) = blocks.first { blocks = blocks.dropFirst() }
        for block in blocks {
            if case .heading(_, let text) = block {
                sections.append(Section(heading: text, blocks: []))
            } else if sections.isEmpty {
                lead.append(block)
            } else {
                sections[sections.count - 1].blocks.append(block)
            }
        }
    }

    init(markdown: String) {
        self.init(MarkdownBlock.parse(markdown))
    }
}

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]

    init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }

    init(markdown: String) {
        self.init(blocks: MarkdownBlock.parse(markdown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(Markdown.render(text))
                        .font(level <= 2 ? .north(.title3).weight(.semibold) : .north(.headline))
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(NorthColor.signal)
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                            .accessibilityHidden(true)
                        prose(text)
                    }
                case .numbered(let number, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(number)
                            .font(.northMono(.caption).weight(.medium))
                            .foregroundStyle(NorthColor.signal)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(NorthColor.signal.opacity(0.12), in: .capsule)
                        prose(text)
                    }
                case .paragraph(let text):
                    prose(text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prose(_ text: String) -> some View {
        Text(Markdown.render(text))
            .font(.north(.body))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
