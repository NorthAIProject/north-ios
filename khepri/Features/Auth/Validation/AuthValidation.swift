import Foundation

public enum AuthValidation {
    public static func isValidEmail(_ email: String) -> Bool {
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    public enum PasswordStrength: Int, CaseIterable, Sendable {
        case veryWeak = 0
        case weak = 1
        case medium = 2
        case strong = 3
        case veryStrong = 4

        public var title: String {
            switch self {
            case .veryWeak: return "Very Weak"
            case .weak: return "Weak"
            case .medium: return "Fair"
            case .strong: return "Good"
            case .veryStrong: return "Strong"
            }
        }
    }

    public static func passwordStrengthScore(_ pass: String) -> Int {
        var score = 0
        if pass.count >= 8 { score += 1 }
        if pass.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if pass.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if pass.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if pass.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",.<>?/~`")) != nil { score += 1 }

        if score <= 1 { return 0 }
        if score == 2 { return 1 }
        if score == 3 { return 2 }
        if score == 4 { return 3 }
        return 4
    }

    public static func passwordStrength(_ pass: String) -> PasswordStrength {
        let score = passwordStrengthScore(pass)
        return PasswordStrength(rawValue: score) ?? .veryWeak
    }
}
