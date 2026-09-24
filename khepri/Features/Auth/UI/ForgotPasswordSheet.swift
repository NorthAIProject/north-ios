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
                    title: "Email address",
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
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send Reset Link")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AuthValidation.isValidEmail(resetEmail) ? Color.accentColor : Color.secondary.opacity(0.3))
                    )
                    .foregroundColor(.white)
                }
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
