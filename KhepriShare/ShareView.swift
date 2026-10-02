import NorthAPI
import NorthKit
import SwiftUI

/// Save what was shared to Knowledge, where the coach can search it, or, for
/// a short line of text, log it the way Capture does: read it, show what will
/// be written, and write only on a yes.
struct ShareView: View {
    let item: SharedItem
    let done: () -> Void

    private enum Phase: Equatable {
        case choosing
        case working
        case confirming([Components.Schemas.CaptureItem])
        case finished(String)
        case failed(String)
    }

    @State private var phase: Phase = .choosing
    @State private var title: String
    @State private var note = ""

    init(item: SharedItem, done: @escaping () -> Void) {
        self.item = item
        self.done = done
        _title = State(initialValue: item.title.isEmpty ? (item.url?.host() ?? "Shared note") : item.title)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Khepri")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: done)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if SharedAPI.client() == nil {
            ContentUnavailableView("Sign in first", systemImage: "person.crop.circle.badge.exclamationmark",
                                   description: Text("Open Khepri and sign in, then share again."))
        } else if item.isEmpty {
            ContentUnavailableView("Nothing to save", systemImage: "square.and.arrow.down",
                                   description: Text("Khepri can save links and text."))
        } else {
            switch phase {
            case .choosing: chooser
            case .working: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .confirming(let items): confirmation(items)
            case .finished(let message): finished(message)
            case .failed(let message): failed(message)
            }
        }
    }

    private var chooser: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                if let url = item.url {
                    Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !item.text.isEmpty {
                    Text(item.text).font(.subheadline).lineLimit(6)
                }
                TextField("Why it matters (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                Text("Save to Knowledge for your coach to draw on, or to the Inbox to decide later.")
            }
            Section {
                Button("Save to Knowledge") { Task { await saveToKnowledge() } }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                // Not sure where it goes: the inbox keeps it, and the coach
                // suggests a home later.
                Button("Save to Inbox") { Task { await saveToInbox() } }
                    .disabled(inboxText.isEmpty)
                if item.isLoggable {
                    Button("Log It Instead") { Task { await parse() } }
                }
            }
        }
    }

    private func confirmation(_ items: [Components.Schemas.CaptureItem]) -> some View {
        Form {
            Section("Log these?") {
                ForEach(Array(items.enumerated()), id: \.offset) { _, captured in
                    Text(captured.source)
                }
            }
            Section {
                Button("Log") { Task { await commit(items) } }
                Button("Back") { phase = .choosing }
            }
        }
    }

    private func finished(_ message: String) -> some View {
        ContentUnavailableView {
            Label(message, systemImage: "checkmark.circle")
        } actions: {
            Button("Done", action: done).buttonStyle(.borderedProminent)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            done()
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("That did not save", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { phase = .choosing }
        }
    }

    /// The note's body: the link first, so the coach can cite it, then what
    /// was quoted, then the person's own words about it.
    private var noteBody: String {
        [item.url?.absoluteString, item.text.isEmpty ? nil : item.text,
         note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Why it matters: \(note)"]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private func saveToKnowledge() async {
        phase = .working
        do {
            let api = try SharedAPI.requireClient()
            _ = try await NorthAPI.call {
                try await api.createKnowledgeNote(body: .json(.init(title: title, body: noteBody))).created
            }
            phase = .finished("Saved to Knowledge")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// What goes to the inbox: the title when it is more than the link
    /// itself, then the same body a note would get.
    private var inboxText: String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return [heading.isEmpty || heading == item.url?.absoluteString ? nil : heading, noteBody.isEmpty ? nil : noteBody]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private func saveToInbox() async {
        phase = .working
        do {
            let api = try SharedAPI.requireClient()
            _ = try await NorthAPI.call {
                try await api.addToInbox(body: .json(.init(text: String(inboxText.prefix(4000)), source: .share))).created
            }
            phase = .finished("Saved to Inbox")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func parse() async {
        phase = .working
        do {
            let api = try SharedAPI.requireClient()
            let parsed = try await NorthAPI.call {
                try await api.parseCapture(body: .json(.init(text: item.text))).ok.body.json
            }
            let writable = parsed.items.filter { $0.problem == nil }
            if writable.isEmpty {
                phase = .failed(parsed.items.compactMap(\.problem).first ?? "Nothing in that could be logged.")
            } else {
                phase = .confirming(writable)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func commit(_ items: [Components.Schemas.CaptureItem]) async {
        phase = .working
        do {
            let api = try SharedAPI.requireClient()
            let result = try await NorthAPI.call {
                try await api.commitCapture(body: .json(.init(items: items))).ok.body.json
            }
            phase = .finished(result.written == 1 ? "Logged" : "Logged \(result.written) things")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
