import AuthenticationServices
import SwiftUI

public struct AppleSignInButton: UIViewRepresentable {
    public let style: ASAuthorizationAppleIDButton.Style
    public let action: () -> Void

    public init(style: ASAuthorizationAppleIDButton.Style = .black, action: @escaping () -> Void) {
        self.style = style
        self.action = action
    }

    public func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: style)
        button.cornerRadius = 12
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    public func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {}
}

public struct SocialAuthButton: View {
    public enum Provider {
        case google
        case passkey

        var title: String {
            switch self {
            case .google: return "Continue with Google"
            case .passkey: return "Sign in with Passkey"
            }
        }

        var iconName: String {
            switch self {
            case .google: return "globe"
            case .passkey: return "person.badge.key.fill"
            }
        }
    }

    let provider: Provider
    let action: () -> Void

    public init(provider: Provider, action: @escaping () -> Void) {
        self.provider = provider
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 16, weight: .semibold))
                Text(provider.title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
