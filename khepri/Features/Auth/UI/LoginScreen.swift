import SwiftUI

public struct LoginScreen: View {
    @StateObject private var viewModel: LoginViewModel
    @Namespace private var animationNamespace

    public init(onAuthenticated: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(onAuthenticated: onAuthenticated))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header Branding
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 72, height: 72)

                            Image(systemName: "compass.drawing")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        .padding(.top, 24)

                        Text("North")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("AI Operating System for Personal Growth")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Mode Switcher (Sign In vs Sign Up)
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.isSignup = false
                                viewModel.clearMessages()
                            }
                        } label: {
                            Text("Sign In")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(viewModel.isSignup ? .secondary : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    ZStack {
                                        if !viewModel.isSignup {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color(uiColor: .systemBackground))
                                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                                                .matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
                                        }
                                    }
                                )
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.isSignup = true
                                viewModel.clearMessages()
                            }
                        } label: {
                            Text("Sign Up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(viewModel.isSignup ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    ZStack {
                                        if viewModel.isSignup {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color(uiColor: .systemBackground))
                                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                                                .matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
                                        }
                                    }
                                )
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )

                    // Error & Info Banners
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.1))
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let info = viewModel.infoMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(info)
                                .font(.footnote)
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green.opacity(0.1))
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Active Form (SignInView or SignUpView)
                    if viewModel.isSignup {
                        SignUpView(viewModel: viewModel)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        SignInView(viewModel: viewModel)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $viewModel.isForgotPasswordPresented) {
                ForgotPasswordSheet(viewModel: viewModel)
            }
        }
    }
}

#Preview {
    LoginScreen()
}
