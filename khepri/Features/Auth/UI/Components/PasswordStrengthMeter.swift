import SwiftUI

public struct PasswordStrengthMeter: View {
    let password: String

    public init(password: String) {
        self.password = password
    }

    private var score: Int {
        AuthValidation.passwordStrengthScore(password)
    }

    private var strength: AuthValidation.PasswordStrength {
        AuthValidation.passwordStrength(password)
    }

    private var color: Color {
        switch score {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .blue
        default: return .green
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= score - 1 ? color : Color(uiColor: .tertiarySystemFill))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.2), value: score)
                }
            }

            if !password.isEmpty {
                HStack {
                    Text("Password Strength: ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(strength.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(color)
                    Spacer()
                }
            }
        }
    }
}
