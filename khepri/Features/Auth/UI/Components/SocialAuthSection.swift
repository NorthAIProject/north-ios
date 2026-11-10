import AuthenticationServices
import SwiftUI

public struct SocialAuthSection: View {
    let onPasskey: (() -> Void)?
    let onApple: () -> Void
    let onGoogle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameter onPasskey: Signs in with a passkey; nil leaves the button out.
    public init(
        onPasskey: (() -> Void)?,
        onApple: @escaping () -> Void,
        onGoogle: @escaping () -> Void
    ) {
        self.onPasskey = onPasskey
        self.onApple = onApple
        self.onGoogle = onGoogle
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 0.5)
                Text("OR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 0.5)
            }
            .padding(.vertical, 8)

            VStack(spacing: 12) {
                if let onPasskey {
                    SocialAuthButton(provider: .passkey, action: onPasskey)
                }

                // Sign in with Apple Button
                AppleSignInButton(
                    style: colorScheme == .dark ? .white : .black,
                    action: onApple
                )
                .frame(minHeight: 50)

                // Google Button
                SocialAuthButton(provider: .google, action: onGoogle)
            }
        }
    }
}
