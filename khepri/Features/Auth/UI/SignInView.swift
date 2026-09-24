import SwiftUI

public struct SignInView: View {
    @ObservedObject var viewModel: LoginViewModel

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Email Field
            VaultTextField(
                title: "Email address",
                systemImage: "envelope.fill",
                text: $viewModel.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )

            // Password Field
            VaultTextField(
                title: "Password",
                systemImage: "lock.fill",
                text: $viewModel.password,
                isSecure: true,
                textContentType: .password
            )

            // Forgot password button
            HStack {
                Spacer()
                Button {
                    viewModel.isForgotPasswordPresented = true
                } label: {
                    Text("Forgot password?")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.top, -4)

            // Submit Button
            Button {
                Task {
                    await viewModel.signIn()
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(viewModel.canSubmitSignIn ? Color.accentColor : Color.secondary.opacity(0.3))
                )
                .foregroundColor(.white)
            }
            .disabled(!viewModel.canSubmitSignIn || viewModel.isLoading)
            .padding(.top, 4)

            // Social Section (Passkey, Apple, Google)
            SocialAuthSection(
                onPasskey: {
                    Task { await viewModel.signInWithPasskey() }
                },
                onApple: {
                    Task { await viewModel.signInWithApple() }
                },
                onGoogle: {
                    Task { await viewModel.signInWithGoogle() }
                }
            )
        }
    }
}
