import NorthAPI
import NorthKit
import SwiftUI
import UniformTypeIdentifiers

/// The library your coach searches: documents and notes, and search the way
/// the coach does it.
struct KnowledgeScreen: View {
    var service: KnowledgeServicing = KnowledgeService()

    @State private var library: KnowledgeList?
    @State private var query = ""
    @State private var hits: [KnowledgeHit] = []
    @State private var error: String?
    @State private var writing = false
    @State private var importing = false
    @State private var uploading = false

    static let fileTypes: [UTType] = [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText]

    var body: some View {
        Group {
            if let library {
                content(library)
            } else if let error {
                ContentUnavailableView("Knowledge did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Knowledge")
        .searchable(text: $query, prompt: "Search your library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Write a Note", systemImage: "square.and.pencil") { writing = true }
                    Button("Add a File", systemImage: "doc.badge.plus") { importing = true }
                    Divider()
                    Button("Re-read Everything", systemImage: "arrow.clockwise") {
                        Task {
                            do { try await service.reindexAll(); await load() } catch { self.error = error.localizedDescription }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $writing) {
            NoteSheet { title, body in
                try await service.createNote(title: title, body: body)
                await load()
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.fileTypes) { result in
            Task { await upload(result) }
        }
        .overlay {
            if uploading { ProgressView("Uploading…").padding().background(.regularMaterial, in: .rect(cornerRadius: 10)) }
        }
        .task { await load() }
        .task(id: query) { await search() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ library: KnowledgeList) -> some View {
        List {
            if let error { ErrorRow(error) }
            if !query.isEmpty {
                Section("Matches") {
                    if hits.isEmpty {
                        Text("Nothing matches yet.")
                            .font(.north(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                        NavigationLink {
                            DocumentTextView(id: hit.documentId, title: hit.title, service: service)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(([hit.title] + hit.headingPath).joined(separator: " › "))
                                    .font(.north(.caption).weight(.medium))
                                    .foregroundStyle(NorthColor.signal)
                                    .lineLimit(1)
                                Text(highlighted(hit))
                                    .font(.north(.subheadline))
                                    .lineSpacing(2)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if !library.documents.isEmpty {
                Section {
                    ForEach(library.documents, id: \.id) { doc in
                        NavigationLink {
                            DocumentTextView(id: doc.id, title: doc.title, service: service, failed: doc.status == .failed)
                        } label: {
                            DocumentRow(document: doc)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task {
                                    do { try await service.delete(doc.id); await load() } catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    }
                } footer: {
                    let counts = library.counts
                    Text("\(counts.ready) ready" + (counts.pending > 0 ? ", \(counts.pending) being read" : "")
                         + (counts.failed > 0 ? ", \(counts.failed) could not be read" : ""))
                        .font(.north(.footnote))
                }
            }
        }
        // An overlay rather than a branch, so the empty library keeps its
        // pull to refresh.
        .overlay {
            if query.isEmpty && library.documents.isEmpty && error == nil {
                EmptyLibrary(onWrite: { writing = true }, onAdd: { importing = true })
            }
        }
    }

    private func load() async {
        do { library = try await service.library(); error = nil } catch { self.error = error.localizedDescription }
    }

    /// The words the search matched, in bold and the signal colour, as the web
/// highlights them.
    private func highlighted(_ hit: KnowledgeHit) -> AttributedString {
        hit.segments.reduce(into: AttributedString()) { text, segment in
            var run = AttributedString(segment.text)
            if segment.matched {
                run.inlinePresentationIntent = .stronglyEmphasized
                run.foregroundColor = NorthColor.signal
            }
            text += run
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { hits = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do { hits = try await service.search(q) } catch { self.error = error.localizedDescription }
    }

    private func upload(_ result: Result<URL, Error>) async {
        uploading = true
        defer { uploading = false }
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try await service.upload(filename: url.lastPathComponent, data: data)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EmptyLibrary: View {
    let onWrite: () -> Void
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "books.vertical")
        } description: {
            Text("Add notes and documents your coach should know: a physio's plan, a race guide, your own training log. It searches them when you ask.")
        } actions: {
            Button("Write a Note", systemImage: "square.and.pencil", action: onWrite)
                .buttonStyle(.borderedProminent)
            Button("Add a File", systemImage: "doc.badge.plus", action: onAdd)
                .buttonStyle(.bordered)
        }
    }
}

private struct DocumentRow: View {
    let document: KnowledgeDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.symbol)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: NorthRadius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.north(.body).weight(.medium))
                    .lineLimit(1)
                status
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        document.status == .failed ? NorthColor.ember : NorthColor.signal
    }

    @ViewBuilder
    private var status: some View {
        switch document.status {
        case .pending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Being read…")
            }
            .font(.north(.caption))
            .foregroundStyle(.secondary)
        case .failed:
            Text(document.failureReason)
                .font(.north(.caption))
                .foregroundStyle(NorthColor.ember)
                .lineLimit(2)
        case .ready:
            Text([document.kindLabel, document.size, document.createdAt.formatted(.relative(presentation: .named))]
                .joined(separator: " · "))
                .font(.north(.caption))
                .foregroundStyle(.secondary)
        }
    }
}

private struct NoteSheet: View {
    let onSave: (String, String) async throws -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Write it down", text: $text, axis: .vertical)
                    .lineLimit(6...20)
                if let error { ErrorRow(error) }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do { try await onSave(title, text); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
