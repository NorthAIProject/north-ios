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
                        Text("Nothing matches yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                        NavigationLink {
                            DocumentTextView(id: hit.documentId, title: hit.title, service: service)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(([hit.title] + hit.headingPath).joined(separator: " › "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(highlighted(hit)).lineLimit(3)
                            }
                        }
                    }
                }
            } else if library.documents.isEmpty {
                Section {
                    Text("Add notes and documents your coach should know: a physio's plan, a race guide, your own training log. It searches them when you ask.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
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
                }
            }
        }
    }

    private func load() async {
        do { library = try await service.library(); error = nil } catch { self.error = error.localizedDescription }
    }

    /// The words the search matched, in bold, as the web highlights them.
    private func highlighted(_ hit: KnowledgeHit) -> AttributedString {
        hit.segments.reduce(into: AttributedString()) { text, segment in
            var run = AttributedString(segment.text)
            if segment.matched { run.inlinePresentationIntent = .stronglyEmphasized }
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

private struct DocumentRow: View {
    let document: KnowledgeDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.kind == "note" ? "note.text" : (document.mime.contains("pdf") ? "doc.richtext" : "doc.text"))
                .foregroundStyle(NorthColor.signal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(document.status == .failed ? NorthColor.ember : .secondary)
            }
        }
    }

    private var status: String {
        switch document.status {
        case .pending: "Being read…"
        case .failed: document.parseError.map { "Could not be read: \($0)" } ?? "Could not be read"
        case .ready: ByteCountFormatter.string(fromByteCount: document.byteSize, countStyle: .file)
        }
    }
}

/// A document as the coach reads it.
private struct DocumentTextView: View {
    let id: String
    let title: String
    let service: KnowledgeServicing
    var failed = false

    @State private var text: String?
    @State private var error: String?
    @State private var queued = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if failed {
                    Button(queued ? "Queued to Read Again" : "Read Again") {
                        Task {
                            do { try await service.reindex(id); queued = true } catch { self.error = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(queued)
                }
                if let text {
                    Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { text = try await service.text(id) } catch { self.error = error.localizedDescription }
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
