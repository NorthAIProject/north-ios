import NorthKit
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

    /// The bars carry the colour; the word stays in the label colour, since
    /// ember is below text contrast on white.
    private var color: Color {
        switch score {
        case 0, 1: NorthColor.destructive
        case 2: NorthColor.ember
        default: NorthColor.signal
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
                        .foregroundStyle(.secondary)
                    Text(strength.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
    }
}
