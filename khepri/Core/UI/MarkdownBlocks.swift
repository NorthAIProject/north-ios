import NorthKit
import SwiftUI

/// Markdown with structure: headings, lists and paragraphs, for the coach's
/// reports and the documents in Knowledge. Chat uses inline Markdown only; a
/// weekly report is a document.
///
/// Deliberately small. It reads the few block forms the coach writes, plus
/// the fences, quotes and rules people put in their own notes, and hands each
/// block's text to the inline renderer; anything else is shown as a paragraph
/// rather than dropped.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(number: String, text: String)
    case paragraph(String)
    /// A fenced block, kept exactly as written: nothing inside is Markdown.
    case code(String)
    case quote(String)
    case rule

    /// A heading and where it sits in the parsed blocks, for a contents list
    /// that jumps to it.
    struct Heading: Equatable {
        var index: Int
        var level: Int
        var text: String
    }

    static func outline(_ blocks: [MarkdownBlock]) -> [Heading] {
        blocks.enumerated().compactMap { index, block in
            guard case .heading(let level, let text) = block else { return nil }
            return Heading(index: index, level: level, text: text)
        }
    }

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var fence: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))) }
            paragraph = []
            quote = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let code = fence {
                if line.hasPrefix("```") || line.hasPrefix("~~~") {
                    blocks.append(.code(code.joined(separator: "\n")))
                    fence = nil
                } else {
                    fence = code + [raw]
                }
            } else if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                fence = []
            } else if line.isEmpty {
                flush()
            } else if line.hasPrefix(">") {
                if !paragraph.isEmpty { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if let block = lineBlock(line) {
                flush()
                blocks.append(block)
            } else {
                if !quote.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        if let code = fence { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }

    /// The blocks that are whole on one line: a rule, a heading or a list
    /// item. The rule is checked first, since `* * *` would otherwise be a
    /// bullet.
    private static func lineBlock(_ line: String) -> MarkdownBlock? {
        if isRule(line) { return .rule }
        if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"),
           line[hashes] == " ", line.distance(from: line.startIndex, to: hashes) <= 6 {
            return .heading(level: line.distance(from: line.startIndex, to: hashes),
                            text: String(line[hashes...]).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return .bullet(String(line.dropFirst(2)))
        }
        if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
           line[line.index(after: dot)...].hasPrefix(" ") {
            return .numbered(number: String(line[..<dot]), text: String(line[line.index(dot, offsetBy: 2)...]))
        }
        return nil
    }

    /// `---`, `***` or `___`, spaced or not.
    private static func isRule(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " }
        guard let mark = marks.first, "-*_".contains(mark), marks.count >= 3 else { return false }
        return marks.allSatisfy { $0 == mark }
    }
}

/// Where a parsed block sits in a scroll view, so a contents list can jump
/// to it. Its own type so it cannot collide with any other id on the page.
struct MarkdownAnchor: Hashable {
    var index: Int
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
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                self.block(block)
                    .id(MarkdownAnchor(index: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ block: MarkdownBlock) -> some View {
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
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.northMono(.footnote))
                    .fixedSize()
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: NorthRadius.medium, style: .continuous))
        case .quote(let text):
            prose(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(NorthColor.signal)
                        .frame(width: 3)
                }
        case .rule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func prose(_ text: String) -> some View {
        Text(Markdown.render(text))
            .font(.north(.body))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
