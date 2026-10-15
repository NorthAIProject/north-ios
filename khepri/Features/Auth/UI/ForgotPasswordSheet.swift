import NorthKit
import SwiftUI

public struct ForgotPasswordSheet: View {
    @ObservedObject var viewModel: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var resetEmail: String = ""
    @State private var isSubmitting: Bool = false

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                        .padding(.top, 16)

                    Text("Reset Password")
                        .font(.title2.weight(.bold))

                    Text("Enter your email address to receive password reset instructions.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                VaultTextField(
                    title: String(localized: "Email address"),
                    systemImage: "envelope.fill",
                    text: $resetEmail,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )

                Button {
                    Task {
                        isSubmitting = true
                        let success = await viewModel.requestPasswordReset(for: resetEmail)
                        isSubmitting = false
                        if success {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if isSubmitting {
                            // The button is disabled while loading, so the system
                            // spinner's grey matches the disabled label.
                            ProgressView()
                        } else {
                            Text("Send Reset Link")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24)
                }
                .northProminentButton()
                .controlSize(.large)
                .disabled(!AuthValidation.isValidEmail(resetEmail) || isSubmitting)

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                resetEmail = viewModel.email
            }
        }
    }
}
