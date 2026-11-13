import NorthKit
import SwiftUI

public struct LoginScreen: View {
    @StateObject private var viewModel: LoginViewModel
    @Namespace private var animationNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onAuthenticated: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(onAuthenticated: onAuthenticated))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header Branding
                    VStack(spacing: 8) {
                        // The emblem in 3D (DESIGN.md, 3D Emblem); flat until its first frame.
                        Emblem3DView(size: 120)
                            .padding(.top, 24)

                        // The brand serif, as in the wordmark. It has one weight.
                        Text(NorthBrand.name)
                            .font(.northDisplay(.largeTitle))
                            .tracking(0.5)

                        Text(NorthBrand.tagline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 0) {
                        modeButton("Sign In", signup: false)
                        modeButton("Sign Up", signup: true)
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: NorthRadius.control, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )

                    // Error & Info Banners
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(NorthColor.destructive)
                                .accessibilityHidden(true)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: NorthRadius.medium, style: .continuous)
                                .fill(NorthColor.destructive.opacity(0.1))
                        )
                        .accessibilityElement(children: .combine)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let info = viewModel.infoMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NorthColor.signal)
                                .accessibilityHidden(true)
                            Text(info)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: NorthRadius.medium, style: .continuous)
                                .fill(NorthColor.signal.opacity(0.1))
                        )
                        .accessibilityElement(children: .combine)
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
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .snappy, value: viewModel.errorMessage)
                .animation(reduceMotion ? nil : .snappy, value: viewModel.infoMessage)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.error, trigger: viewModel.errorMessage) { _, message in message != nil }
            .onChange(of: viewModel.errorMessage) { _, message in announce(message) }
            .onChange(of: viewModel.infoMessage) { _, message in announce(message) }
            .sheet(isPresented: $viewModel.isForgotPasswordPresented) {
                ForgotPasswordSheet(viewModel: viewModel)
            }
        }
    }

    private func modeButton(_ title: LocalizedStringKey, signup: Bool) -> some View {
        let isSelected = viewModel.isSignup == signup
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isSignup = signup
                viewModel.clearMessages()
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: NorthRadius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                            .overlay {
                                RoundedRectangle(cornerRadius: NorthRadius.medium, style: .continuous)
                                    .strokeBorder(NorthColor.hairline, lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
                    }
                }
                .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func announce(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

#Preview {
    LoginScreen()
}
