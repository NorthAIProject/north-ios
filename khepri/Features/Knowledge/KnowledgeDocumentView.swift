import NorthAPI
import NorthKit
import SwiftUI

/// A document as the coach reads it: what it is, its contents, then the text
/// with its Markdown drawn rather than shown.
struct DocumentTextView: View {
    let id: String
    let title: String
    let service: KnowledgeServicing
    var failed = false

    @State private var document: KnowledgeDocument?
    @State private var blocks: [MarkdownBlock] = []
    @State private var error: String?
    @State private var queued = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let document {
                        DocumentHeader(document: document)
                    }
                    if failed || document?.status == .failed {
                        Button(queued ? "Queued to Read Again" : "Read Again", systemImage: "arrow.clockwise") {
                            Task {
                                do { try await service.reindex(id); queued = true } catch { self.error = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(queued)
                    }
                    if let error {
                        Text(error)
                            .font(.north(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    if let document {
                        let outline = MarkdownBlock.outline(blocks)
                        if outline.count > 1 {
                            DocumentContents(headings: outline) { heading in
                                withAnimation { proxy.scrollTo(MarkdownAnchor(index: heading.index), anchor: .top) }
                            }
                        }
                        if blocks.isEmpty {
                            (document.status == .pending
                                 ? Text("Still being read. The text appears here when it is done.")
                                 : Text("There is no text in this document."))
                                .font(.north(.subheadline))
                                .foregroundStyle(.secondary)
                        } else {
                            MarkdownBlocksView(blocks: blocks)
                                .textSelection(.enabled)
                        }
                    } else if error == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let detail = try await service.document(id)
                document = detail.value1
                blocks = MarkdownBlock.parse(detail.value2.text)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct DocumentHeader: View {
    let document: KnowledgeDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(document.kindLabel, systemImage: document.symbol)
                    .northEyebrow(NorthColor.signal)
                Text(document.title)
                    .font(.north(.title).weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if document.status == .failed {
                    Text(document.failureReason)
                        .font(.north(.subheadline))
                        .foregroundStyle(NorthColor.ember)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { facts }
                VStack(alignment: .leading, spacing: 12) { facts }
            }
        }
    }

    @ViewBuilder
    private var facts: some View {
        Fact(label: "Kind", value: document.kindLabel)
        Fact(label: "Size", value: document.size)
        Fact(label: "Read", value: read)
    }

    private var read: String {
        switch document.status {
        case .pending: String(localized: "Being read…")
        case .failed: String(localized: "Failed")
        case .ready:
            document.indexedAt.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "Ready")
        }
    }
}

private struct Fact: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).northEyebrow()
            Text(value)
                .font(.north(.subheadline))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The document's headings, each jumping to where it sits in the text.
private struct DocumentContents: View {
    let headings: [MarkdownBlock.Heading]
    let onSelect: (MarkdownBlock.Heading) -> Void

    var body: some View {
        let top = headings.map(\.level).min() ?? 1
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader(String(localized: "Contents"))
            ForEach(headings, id: \.index) { heading in
                Button { onSelect(heading) } label: {
                    Text(Markdown.render(heading.text))
                        .font(.north(.subheadline).weight(heading.level == top ? .medium : .regular))
                        .foregroundStyle(heading.level == top ? .primary : .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, CGFloat(min(heading.level - top, 3)) * 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .northSurfaceCard()
    }
}

/// How a document names itself on screen, shared by the list and the reader.
extension KnowledgeDocument {
    var symbol: String {
        kind == "note" ? "note.text" : (mime.contains("pdf") ? "doc.richtext" : "doc.text")
    }

    /// The same names the web shows.
    var kindLabel: String {
        let mime = mime.lowercased()
        if kind == "note" { return String(localized: "Note") }
        if mime.contains("pdf") { return "PDF" }
        if mime.contains("markdown") { return String(localized: "Markdown") }
        if mime.contains("csv") { return "CSV" }
        return String(localized: "Text", comment: "Kind of document: plain text")
    }

    var size: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var failureReason: String {
        parseError.map { String(localized: "Could not be read: \($0)") } ?? String(localized: "Could not be read")
    }
}
