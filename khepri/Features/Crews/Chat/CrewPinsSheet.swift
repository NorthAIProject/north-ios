import NorthAPI
import NorthKit
import SwiftUI

/// The open channel's pinned messages, newest pin first as the server sends them.
/// Someone else's pin can be reported and its author blocked, as in the channel.
struct CrewPinsSheet: View {
    let store: CrewChatStore
    let role: CrewRole
    let service: CrewChatServicing

    @State private var pins: [CrewMessage]?
    @State private var error: String?
    @State private var reporting: CrewMessage?
    @State private var blocking: CrewMessage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorRow(error) }
                if let pins {
                    if pins.isEmpty {
                        Text("Nothing pinned yet.").foregroundStyle(.secondary)
                    }
                    ForEach(pins) { message in
                        PinRow(message: message)
                            .contextMenu {
                                let actions = CrewMessageActions.moderation(for: message, meID: store.meID, role: role)
                                ForEach(actions, id: \.self) { action in
                                    CrewMessageMenuItem(action: action, authorName: message.authorName) {
                                        if action == .report { reporting = message } else { blocking = message }
                                    }
                                }
                            }
                    }
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Pinned messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $reporting) { message in
                CrewReportSheet { reason, note in
                    Task { await report(message, reason: reason, note: note) }
                }
            }
            .confirmationDialog(
                Text("Block \(blocking?.authorName ?? "")? You won't see each other's messages."),
                isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                titleVisibility: .visible,
                presenting: blocking
            ) { message in
                Button("Block", role: .destructive) {
                    Task { await block(authorOf: message) }
                }
            }
        }
    }

    /// Through the channel's store, so the message leaves the channel too.
    private func report(_ message: CrewMessage, reason: String, note: String?) async {
        pins?.removeAll { $0.id == message.id }
        await store.report(message, reason: reason, note: note)
        await load()
    }

    private func block(authorOf message: CrewMessage) async {
        let author = message.author?.value1.id
        pins?.removeAll { $0.author?.value1.id == author }
        await store.block(authorOf: message)
        await load()
    }

    private func load() async {
        do {
            pins = try await service.pins(store.crewID, channel: store.channelID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PinRow: View {
    let message: CrewMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(message.authorName).font(.subheadline.weight(.semibold))
                if let date = message.createdAt {
                    Text(CrewTime.short(date)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if message.deleted == true {
                Text("This message was deleted.").italic().foregroundStyle(.secondary)
            } else {
                CrewMessageText(text: message.body ?? "", edited: message.edited == true)
            }
        }
        .padding(.vertical, 2)
    }
}
