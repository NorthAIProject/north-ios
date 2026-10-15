import SwiftUI

/// Light, dark, or following the phone. Applies at once and is kept on this
/// iPhone even when the account cannot be reached.
struct AppearancePicker: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?

    var body: some View {
        Picker(selection: selection) {
            ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
        } label: {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
        }
        if let error { ErrorRow(error) }
    }

    private var selection: Binding<AppearanceSetting> {
        Binding(get: { app.appearance }, set: { choice in
            app.chooseAppearance(choice)
            Task {
                do {
                    try await app.saveAppearanceToAccount()
                    error = nil
                } catch {
                    let reason = error.localizedDescription
                    self.error = String(localized: "Saved on this iPhone, but not to your account: \(reason)")
                }
            }
        })
    }
}
