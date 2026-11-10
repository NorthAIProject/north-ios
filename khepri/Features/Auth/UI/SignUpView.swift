import NorthKit
import SwiftUI

public struct SignUpView: View {
    @ObservedObject var viewModel: LoginViewModel
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmationFocused: Bool

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Display Name
            VaultTextField(
                title: String(localized: "Your name"),
                systemImage: "person.fill",
                text: $viewModel.displayName,
                autoCapitalization: .words,
                submitLabel: .next,
                onSubmit: { emailFocused = true }
            )

            // Email Field
            VaultTextField(
                title: String(localized: "Email address"),
                systemImage: "envelope.fill",
                text: $viewModel.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                submitLabel: .next,
                focus: $emailFocused,
                onSubmit: { passwordFocused = true }
            )

            // Password Field
            VaultTextField(
                title: String(localized: "Password (min 8 characters)"),
                systemImage: "lock.fill",
                text: $viewModel.password,
                isSecure: true,
                textContentType: .newPassword,
                submitLabel: .next,
                focus: $passwordFocused,
                onSubmit: { confirmationFocused = true }
            )

            if !viewModel.password.isEmpty {
                PasswordStrengthMeter(password: viewModel.password)
            }

            // Confirm Password Field
            VaultTextField(
                title: String(localized: "Confirm password"),
                systemImage: "checkmark.shield.fill",
                text: $viewModel.passwordConfirmation,
                isSecure: true,
                textContentType: .newPassword,
                submitLabel: .go,
                focus: $confirmationFocused,
                onSubmit: {
                    guard viewModel.canSubmitSignUp, !viewModel.isLoading else { return }
                    Task { await viewModel.signUp() }
                }
            )

            if !viewModel.passwordConfirmation.isEmpty && viewModel.password != viewModel.passwordConfirmation {
                HStack {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundStyle(NorthColor.destructive)
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
                        // The button is disabled while loading; the spinner takes its colour
                        // from tint, so it is set to match the disabled label.
                        ProgressView()
                            .tint(.secondary)
                    } else {
                        Text("Create Account")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .northProminentButton()
            .controlSize(.large)
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
                        .font(.subheadline)
                    Text("Or create account with a Passkey")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
            }
            .disabled(viewModel.isLoading)

            // Social Section (Apple & Google for registration)
            SocialAuthSection(
                onPasskey: nil,
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
