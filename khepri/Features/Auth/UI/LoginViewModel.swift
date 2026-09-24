import Combine
import Foundation
import SwiftUI

@MainActor
public final class LoginViewModel: ObservableObject {
    @Published public var email = ""
    @Published public var password = ""
    @Published public var passwordConfirmation = ""
    @Published public var displayName = ""

    @Published public var isSignup = false
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var infoMessage: String?
    @Published public var isForgotPasswordPresented = false

    private let authService: AuthServicing
    private let onAuthenticated: () -> Void

    public init(
        authService: AuthServicing = AuthService.shared,
        onAuthenticated: @escaping () -> Void = {}
    ) {
        self.authService = authService
        self.onAuthenticated = onAuthenticated
    }

    public var canSubmitSignIn: Bool {
        AuthValidation.isValidEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)) &&
        !password.isEmpty
    }

    public var canSubmitSignUp: Bool {
        AuthValidation.isValidEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)) &&
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 8 &&
        password == passwordConfirmation
    }

    public func signIn() async {
        guard canSubmitSignIn, !isLoading else { return }
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authService.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func signUp() async {
        guard canSubmitSignUp, !isLoading else { return }
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authService.signup(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                passwordConfirmation: passwordConfirmation,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func signInWithGoogle() async {
        guard !isLoading else { return }
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authService.signInWithGoogle()
            onAuthenticated()
        } catch {
            if let oauthErr = error as? OAuthWebAuthenticationError, oauthErr == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    public func signInWithApple() async {
        guard !isLoading else { return }
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authService.signInWithApple()
            onAuthenticated()
        } catch {
            if let oauthErr = error as? OAuthWebAuthenticationError, oauthErr == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    public func signInWithPasskey() async {
        guard !isLoading else { return }
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authService.signInWithPasskey()
            onAuthenticated()
        } catch {
            if let oauthErr = error as? OAuthWebAuthenticationError, oauthErr == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    public func registerWithPasskey() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AuthValidation.isValidEmail(trimmedEmail), !trimmedName.isEmpty, !isLoading else {
            errorMessage = "Please enter a valid email and display name first."
            return
        }

        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authService.registerPasskey(email: trimmedEmail, displayName: trimmedName)
            onAuthenticated()
        } catch {
            if let oauthErr = error as? OAuthWebAuthenticationError, oauthErr == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    public func requestPasswordReset(for emailToReset: String) async -> Bool {
        guard AuthValidation.isValidEmail(emailToReset) else {
            errorMessage = "Please enter a valid email address."
            return false
        }
        do {
            try await authService.forgotPassword(email: emailToReset)
            infoMessage = "If that email is registered, password reset instructions have been sent."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }
}
