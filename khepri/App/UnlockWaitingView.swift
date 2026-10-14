import NorthKit
import SwiftUI

/// Shown when the app launched before the phone was first unlocked after a
/// restart. The session is there but unreadable until then, so this asks for
/// the unlock rather than offering a sign-in the person does not need.
struct UnlockWaitingView: View {
    var body: some View {
        VStack(spacing: 20) {
            NorthBrand.mark
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Unlock your iPhone to continue")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    UnlockWaitingView()
}
