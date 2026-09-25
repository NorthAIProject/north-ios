import NorthAPI
import NorthKit
import SwiftUI

typealias Journal = Components.Schemas.Journal

protocol JournalServicing: Sendable {
    func journal() async throws -> Journal
    func write(_ content: String, mood: Int?) async throws
}

struct JournalService: JournalServicing {
    var api: Client = API.shared

    func journal() async throws -> Journal {
        try await NorthAPI.call { try await api.getJournal().ok.body.json }
    }

    func write(_ content: String, mood: Int?) async throws {
        try await NorthAPI.call { _ = try await api.writeJournal(body: .json(.init(content: content, mood: mood))).created }
    }
}

/// A private journal: what is on your mind, with how you have been feeling
/// beside it. The coach reads it for context; nobody else does.
struct JournalScreen: View {
    var service: JournalServicing = JournalService()
    @State private var journal: Journal?
    @State private var error: String?
    @State private var writing = false

    var body: some View {
        Group {
            if let journal {
                List {
                    if let error { ErrorRow(error) }
                    if journal.trend.count > 0 {
                        Section {
                            HStack(spacing: 32) {
                                stat(journal.trend.averageMood, "MOOD")
                                stat(journal.trend.averageEnergy, "ENERGY")
                            }
                            .padding(.vertical, 4)
                        } footer: {
                            Text("Average of your last \(journal.trend.count) check-ins, out of 5.")
                        }
                    }
                    Section {
                        if journal.entries.isEmpty {
                            Text("Nothing written yet.").foregroundStyle(.secondary)
                        }
                        ForEach(journal.entries, id: \.id) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.content)
                                HStack(spacing: 8) {
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    if let mood = entry.mood { Text("Mood \(mood)") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView("The journal did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Write", systemImage: "square.and.pencil") { writing = true }
            }
        }
        .sheet(isPresented: $writing) {
            JournalSheet { content, mood in
                try await service.write(content, mood: mood)
                await load()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { journal = try await service.journal(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func stat(_ value: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted(.number.precision(.fractionLength(1)))).font(.system(size: 24, weight: .light).monospacedDigit())
            Text(label).font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
        }
    }
}

private struct JournalSheet: View {
    let onSave: (String, Int?) async throws -> Void
    @State private var content = ""
    @State private var withMood = false
    @State private var mood = 3
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("What's on your mind?", text: $content, axis: .vertical)
                    .lineLimit(6...20)
                Toggle("Add how you feel", isOn: $withMood)
                if withMood {
                    Picker("Mood", selection: $mood) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do { try await onSave(content, withMood ? mood : nil); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
