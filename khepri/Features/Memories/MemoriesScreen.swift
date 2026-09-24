import NorthAPI
import NorthKit
import SwiftUI

typealias Memory = Components.Schemas.Memory

protocol MemoriesServicing: Sendable {
    func memories() async throws -> Components.Schemas.MemoryList
    func create(category: String, content: String) async throws
    func update(_ id: String, category: String, content: String) async throws
    func approve(_ id: String) async throws
    func reject(_ id: String) async throws
    func setUse(_ id: String, _ use: MemoryUse) async throws
    func delete(_ id: String) async throws
}

/// Whether the coach sees a memory. The server keeps pinned and excluded
/// exclusive, so the app offers them as one three-way choice.
enum MemoryUse: String, CaseIterable, Identifiable {
    case normally, always, never

    var id: String { rawValue }

    init(_ memory: Memory) {
        self = memory.pinned ? .always : memory.excluded ? .never : .normally
    }

    var label: String {
        switch self {
        case .normally: "When Relevant"
        case .always: "Always"
        case .never: "Never"
        }
    }
}

struct MemoriesService: MemoriesServicing {
    var api: Client = API.shared

    func memories() async throws -> Components.Schemas.MemoryList {
        try await NorthAPI.call { try await api.listMemories().ok.body.json }
    }

    func create(category: String, content: String) async throws {
        try await NorthAPI.call { _ = try await api.createMemory(body: .json(.init(category: category, content: content))).created }
    }

    func update(_ id: String, category: String, content: String) async throws {
        try await NorthAPI.call {
            _ = try await api.updateMemory(path: .init(memoryID: id), body: .json(.init(category: category, content: content))).ok
        }
    }

    func approve(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.approveMemory(path: .init(memoryID: id)).ok }
    }

    func reject(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.rejectMemory(path: .init(memoryID: id)).ok }
    }

    func setUse(_ id: String, _ use: MemoryUse) async throws {
        try await NorthAPI.call {
            switch use {
            case .always:
                _ = try await api.setMemoryPinned(path: .init(memoryID: id), body: .json(.init(value: true))).ok
            case .never:
                _ = try await api.setMemoryExcluded(path: .init(memoryID: id), body: .json(.init(value: true))).ok
            case .normally:
                // Clearing either flag clears both.
                _ = try await api.setMemoryExcluded(path: .init(memoryID: id), body: .json(.init(value: false))).ok
            }
        }
    }

    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteMemory(path: .init(memoryID: id)).noContent }
    }
}

/// What the coach remembers about you, and what it has noticed and wants to
/// keep. Nothing it proposes is used until you say so.
struct MemoriesScreen: View {
    var service: MemoriesServicing = MemoriesService()
    @State private var list: Components.Schemas.MemoryList?
    @State private var error: String?
    @State private var adding = false
    @State private var editing: Memory?

    var body: some View {
        Group {
            if let list {
                content(list)
            } else if let error {
                ContentUnavailableView("Memories did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Memories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Memory", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            MemoryForm(title: "Add Memory", categories: list?.categories ?? [], category: "general", content: "") { category, content in
                try await service.create(category: category, content: content)
                await load()
            }
        }
        .sheet(item: $editing) { memory in
            MemoryForm(title: "Edit Memory", categories: list?.categories ?? [], category: memory.category, content: memory.content) { category, content in
                try await service.update(memory.id, category: category, content: content)
                await load()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func content(_ list: Components.Schemas.MemoryList) -> some View {
        List {
            if let error { ErrorRow(error) }

            if !list.pending.isEmpty {
                Section {
                    ForEach(list.pending, id: \.id) { memory in
                        VStack(alignment: .leading, spacing: 8) {
                            MemoryText(memory: memory)
                            HStack(spacing: 12) {
                                Button("Keep") { act { try await service.approve(memory.id) } }
                                    .buttonStyle(.borderedProminent)
                                Button("Discard") { act { try await service.reject(memory.id) } }
                                    .buttonStyle(.bordered)
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Waiting for You")
                } footer: {
                    Text("Things your coach noticed in conversation. It uses none of them until you keep them.")
                }
            }

            Section {
                if list.approved.isEmpty {
                    Text("Nothing yet. Add something your coach should always know, like an old injury or when you train.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(list.approved, id: \.id) { memory in
                    MemoryText(memory: memory)
                        .contextMenu {
                            Picker("Use", selection: Binding(
                                get: { MemoryUse(memory) },
                                set: { use in act { try await service.setUse(memory.id, use) } }
                            )) {
                                ForEach(MemoryUse.allCases) { Text($0.label).tag($0) }
                            }
                            Button("Edit", systemImage: "pencil") { editing = memory }
                            Button("Forget", systemImage: "trash", role: .destructive) { act { try await service.delete(memory.id) } }
                        }
                        .swipeActions {
                            Button("Forget", role: .destructive) { act { try await service.delete(memory.id) } }
                        }
                }
            } header: {
                Text("Remembered")
            } footer: {
                if !list.approved.isEmpty {
                    Text("Touch and hold to choose when your coach uses one, to edit it, or to forget it.")
                }
            }
        }
    }

    private func load() async {
        do { list = try await service.memories(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func act(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); await load() } catch { self.error = error.localizedDescription }
        }
    }
}

extension Memory: Identifiable {}

private struct MemoryText: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.content)
                .foregroundStyle(memory.excluded ? .secondary : .primary)
            HStack(spacing: 8) {
                Text(memory.category.capitalized)
                switch MemoryUse(memory) {
                case .always: Label("Always used", systemImage: "pin.fill").foregroundStyle(NorthColor.signal)
                case .never: Label("Not used", systemImage: "eye.slash")
                case .normally: EmptyView()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MemoryForm: View {
    let title: String
    let categories: [String]
    @State var category: String
    @State var content: String
    let onSave: (String, String) async throws -> Void

    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("What should your coach know?", text: $content, axis: .vertical)
                    .lineLimit(2...6)
                Picker("Kind", selection: $category) {
                    ForEach(categories.isEmpty ? ["general"] : categories, id: \.self) { Text($0.capitalized).tag($0) }
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do { try await onSave(category, content); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
