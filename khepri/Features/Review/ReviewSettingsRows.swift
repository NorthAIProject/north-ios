import SwiftUI

/// Settings rows: a link to write a review, and the switch for the in-app ask.
/// The link is hidden until the app has an App Store ID.
struct ReviewSettingsRows: View {
    @Bindable var prompter: ReviewPrompter = .shared
    var appStoreID: String? = AppEnvironment.appStoreID

    var body: some View {
        if let appStoreID, let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") {
            Link(destination: url) {
                Label("Rate Khepri on the App Store", systemImage: "star")
            }
        }
        Toggle(isOn: $prompter.isEnabled) {
            Label("Ask me to rate Khepri", systemImage: "star.bubble")
        }
    }
}
