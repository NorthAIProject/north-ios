import SwiftUI

public struct SignUpView: View {
    @ObservedObject var viewModel: LoginViewModel

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Display Name
            VaultTextField(
                title: "Your name",
                systemImage: "person.fill",
                text: $viewModel.displayName,
                autoCapitalization: .words
            )

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
                title: "Password (min 8 characters)",
                systemImage: "lock.fill",
                text: $viewModel.password,
                isSecure: true,
                textContentType: .newPassword
            )

            if !viewModel.password.isEmpty {
                PasswordStrengthMeter(password: viewModel.password)
            }

            // Confirm Password Field
            VaultTextField(
                title: "Confirm password",
                systemImage: "checkmark.shield.fill",
                text: $viewModel.passwordConfirmation,
                isSecure: true,
                textContentType: .newPassword
            )

            if !viewModel.passwordConfirmation.isEmpty && viewModel.password != viewModel.passwordConfirmation {
                HStack {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.top, -8)
            }

            // Submit Button
            Button {
                Task {
                    await viewModel.signUp()
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Create Account")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(viewModel.canSubmitSignUp ? Color.accentColor : Color.secondary.opacity(0.3))
                )
                .foregroundColor(.white)
            }
            .disabled(!viewModel.canSubmitSignUp || viewModel.isLoading)
            .padding(.top, 4)

            // Passkey Register Option
            Button {
                Task {
                    await viewModel.registerWithPasskey()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 15))
                    Text("Or create account with a Passkey")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.accentColor)
                .padding(.top, 4)
            }
            .disabled(viewModel.isLoading)

            // Social Section (Apple & Google for registration)
            SocialAuthSection(
                onPasskey: {
                    Task { await viewModel.registerWithPasskey() }
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
