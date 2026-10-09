import NorthAPI
import NorthKit
import SwiftUI

extension ChatAttachment {
    /// `kind` is an open string: "image" is a photo, anything else a document.
    var isPhoto: Bool { kind == "image" }

    var systemImage: String { isPhoto ? "photo" : "doc" }

    var accessibilityDescription: String { "\(isPhoto ? "Photo" : "Document"), \(name)" }
}

/// A sent photo or document, by name, inside a message.
struct AttachmentChip: View {
    let attachment: ChatAttachment

    var body: some View {
        Label(attachment.name, systemImage: attachment.systemImage)
            .font(.footnote)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(attachment.accessibilityDescription)
    }
}

/// What the next message will carry, above the composer: the file still
/// uploading, the one ready to send, or why it could not be attached.
struct PendingAttachmentBar: View {
    let attachment: ChatAttachment?
    let uploadingName: String?
    let error: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let uploadingName {
                chip(uploadingName, accessibilityLabel: "Uploading \(uploadingName)", removeLabel: "Cancel upload") {
                    ProgressView().controlSize(.small)
                }
            } else if let attachment {
                chip(
                    attachment.name,
                    accessibilityLabel: attachment.accessibilityDescription,
                    removeLabel: "Remove attachment"
                ) {
                    Image(systemName: attachment.systemImage)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(NorthColor.destructive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(
        _ name: String,
        accessibilityLabel: String,
        removeLabel: String,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                icon()
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeLabel)
        }
        .font(.footnote)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: .capsule)
    }
}
