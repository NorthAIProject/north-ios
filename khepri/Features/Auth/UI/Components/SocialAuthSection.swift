import AuthenticationServices
import SwiftUI

public struct SocialAuthSection: View {
    let onPasskey: () -> Void
    let onApple: () -> Void
    let onGoogle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        onPasskey: @escaping () -> Void,
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
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 0.5)
            }
            .padding(.vertical, 8)

            VStack(spacing: 12) {
                // Passkey Button
                SocialAuthButton(provider: .passkey, action: onPasskey)

                // Sign in with Apple Button
                AppleSignInButton(
                    style: colorScheme == .dark ? .white : .black,
                    action: onApple
                )
                .frame(height: 50)

                // Google Button
                SocialAuthButton(provider: .google, action: onGoogle)
            }
        }
    }
}
