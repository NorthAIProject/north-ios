import NorthAPI
import NorthKit
import SwiftUI

/// The open channel's pinned messages, newest pin first as the server sends them.
struct CrewPinsSheet: View {
    let crewID: String
    let channelID: String
    let service: CrewChatServicing

    @State private var pins: [CrewMessage]?
    @State private var error: String?
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
        }
    }

    private func load() async {
        do {
            pins = try await service.pins(crewID, channel: channelID)
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
