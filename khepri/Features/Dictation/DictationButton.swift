import NorthKit
import SwiftUI

extension EnvironmentValues {
    /// Who listens when a microphone is tapped. The UI tests hear a fixed
    /// sentence, since the simulator has no microphone to speak into.
    @Entry var speechTranscriber: any SpeechTranscribing = {
        #if DEBUG
        if UITesting.isActive { return ScriptedTranscriber() }
        #endif
        return OnDeviceTranscriber()
    }()
}

/// A microphone that writes what the person says into `text`.
///
/// Absent where this iPhone cannot transcribe the person's language. The
/// first tap says why the microphone is wanted before iOS asks, because a
/// refusal can only be undone in the Settings app.
struct DictationButton: View {
    @Binding var text: String
    var font: Font = .title
    /// Told when listening starts and stops, so a screen can show it too.
    var onListeningChange: (Bool) -> Void = { _ in }

    @Environment(\.speechTranscriber) private var transcriber
    @Environment(\.openURL) private var openURL
    @State private var controller: DictationController?
    @State private var explaining = false
    @State private var refused = false

    var body: some View {
        // A ZStack, not a Group: a Group hands its modifiers to its children,
        // and this one starts with none, so the task that makes the controller
        // never ran and the microphone never appeared.
        ZStack {
            if let controller, controller.isAvailable {
                button(controller)
            }
        }
        .task {
            let controller = DictationController(transcriber: transcriber)
            self.controller = controller
            await controller.checkAvailability()
        }
        .onChange(of: controller?.phase == .listening) { _, listening in onListeningChange(listening) }
        .onDisappear {
            controller?.cancel()
            onListeningChange(false)
        }
    }

    private func button(_ controller: DictationController) -> some View {
        Button {
            tap(controller)
        } label: {
            Image(systemName: controller.isActive ? "mic.fill" : "mic")
                .font(font)
                .symbolEffect(.variableColor.iterative, isActive: controller.phase == .listening)
                .foregroundStyle(controller.isActive ? NorthColor.signal : .secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controller.isActive ? "Stop dictating" : "Dictate")
        .accessibilityIdentifier("dictate")
        .sensoryFeedback(.start, trigger: controller.phase == .listening) { _, listening in listening }
        .alert("Speak instead of typing", isPresented: $explaining) {
            Button("Continue") {
                Task {
                    if await Permissions.requestDictation() {
                        controller.start($text)
                    } else {
                        refused = true
                    }
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Khepri needs the microphone to hear you. Your words are turned into text on this iPhone and appear in the box for you to check before sending.")
        }
        .alert("Dictation is off", isPresented: $refused) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow the microphone and speech recognition for Khepri in Settings to dictate.")
        }
        .alert("Could not listen", isPresented: Binding(
            get: { if case .failed = controller.phase { true } else { false } },
            set: { if !$0 { controller.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let message) = controller.phase { Text(message) }
        }
    }

    private func tap(_ controller: DictationController) {
        if controller.isActive || UITesting.isActive {
            controller.toggle($text)
            return
        }
        switch Permissions.dictation {
        case .granted: controller.start($text)
        case .undetermined: explaining = true
        case .denied: refused = true
        }
    }
}
