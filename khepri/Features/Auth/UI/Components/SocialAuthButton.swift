import AuthenticationServices
import NorthKit
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
        button.cornerRadius = NorthRadius.control
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
            case .google: return String(localized: "Continue with Google")
            case .passkey: return String(localized: "Sign in with Passkey")
            }
        }

        /// Google's four-colour mark as drawn, never tinted; an SF Symbol for the passkey.
        @ViewBuilder
        func icon(markSize: CGFloat) -> some View {
            switch self {
            case .google:
                Image("GoogleMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: markSize, height: markSize)
            case .passkey:
                Image(systemName: "person.badge.key.fill")
                    .font(.callout.weight(.semibold))
            }
        }
    }

    let provider: Provider
    let action: () -> Void
    @ScaledMetric(relativeTo: .callout) private var markSize: CGFloat = 18

    public init(provider: Provider, action: @escaping () -> Void) {
        self.provider = provider
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                provider.icon(markSize: markSize)
                    .accessibilityHidden(true)
                Text(provider.title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: NorthRadius.control, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NorthRadius.control, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
