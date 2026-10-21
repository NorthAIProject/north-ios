import SwiftUI

/// The message field shared by the coach and crew chat: text, optional
/// attach, optional dictation, and send (or stop while a reply is running).
struct ChatComposer<Attachments: View>: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    /// A reply is running. With `onStop` the send button becomes stop and
    /// dictation hides; without it the send button just follows `canSend`.
    let isBusy: Bool
    /// Whether the message as typed, with its file, can go now.
    let canSend: Bool
    var focused: FocusState<Bool>.Binding
    var dictation: Bool = true
    /// Called when dictation starts or stops listening.
    var onListeningChange: (Bool) -> Void = { _ in }
    var onAttach: (() -> Void)?
    let onSend: () -> Void
    var onStop: (() -> Void)?
    /// The file the next message carries, shown above the field.
    @ViewBuilder let attachments: () -> Attachments

    var body: some View {
        VStack(spacing: 8) {
            attachments()
            HStack(alignment: .bottom, spacing: 8) {
                if let onAttach {
                    Button(action: onAttach) {
                        Image(systemName: "paperclip").font(.title3)
                    }
                    .padding(.bottom, 6)
                    .accessibilityLabel("Attach a file or photo")
                }

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    // The placeholder names the field only while it is empty.
                    .accessibilityIdentifier("composer")
                    .focused(focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))

                // The keyboard's microphone only appears once the keyboard is up
                // and stops on a pause; this one is a tap away and keeps
                // listening until tapped again.
                if dictation, !isBusy {
                    DictationButton(text: $text, onListeningChange: onListeningChange)
                }

                if isBusy, let onStop {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill").font(.title)
                    }
                    .accessibilityLabel("Stop")
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
