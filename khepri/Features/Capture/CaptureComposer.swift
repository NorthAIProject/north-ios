import NorthAPI
import SwiftUI
import WidgetKit

/// Type or say what happened, check what the model read, then log it.
///
/// Rows for a Form or List section. Nothing is written until the person taps
/// Log, because the reading is the model's guess and only they know what
/// they meant.
struct CaptureComposer: View {
    let prompt: LocalizedStringKey
    /// Called after something was saved, so the screen can reload.
    let onLogged: () -> Void

    @State private var draft: CaptureDraft

    init(
        prompt: LocalizedStringKey = "Drank 500 ml and slept 7 hours…",
        service: CaptureServicing? = nil,
        onLogged: @escaping () -> Void = {}
    ) {
        self.prompt = prompt
        self.onLogged = onLogged
        _draft = State(initialValue: CaptureDraft(service: service))
    }

    var body: some View {
        HStack(alignment: .top) {
            TextField(prompt, text: $draft.text, axis: .vertical)
                .lineLimit(2...5)
            DictationButton(text: $draft.text, font: .title3)
        }
        Button {
            Task { await draft.review() }
        } label: {
            if draft.isBusy, !draft.hasReading {
                ProgressView()
            } else {
                Text(draft.hasReading ? "Read again" : "Review")
            }
        }
        .disabled(!draft.canReview)

        ForEach(draft.items.indices, id: \.self) { index in
            CaptureItemRow(item: draft.items[index], isOn: Binding(
                get: { draft.isChosen(index) },
                set: { draft.setChosen(index, $0) }
            ))
            .disabled(!draft.isWritable(index) || draft.isBusy)
        }
        if !draft.unparsed.isEmpty {
            Text("Not understood: \(draft.unparsed.joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if draft.hasReading {
            Button("Log \(draft.itemsToLog.count)") {
                Task {
                    guard await draft.log() else { return }
                    WidgetCenter.shared.reloadAllTimelines()
                    onLogged()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canLog)
        }
        if let result = draft.result {
            Label(result, systemImage: "checkmark.circle").foregroundStyle(.secondary)
        }
        if let error = draft.error {
            Text(error).foregroundStyle(.red)
        }
    }
}

/// One thing the model read, with a switch to keep or drop it. An item the
/// server cannot write shows why instead of a working switch.
private struct CaptureItemRow: View {
    let item: CaptureItem
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.source)
                Text(item.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let problem = item.problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                } else if item.uncertain == true {
                    Label("Not sure, check this", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .opacity(item.problem == nil ? 1 : 0.5)
    }
}
