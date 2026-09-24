import SwiftUI

public struct VaultTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autoCapitalization: TextInputAutocapitalization = .never

    @State private var isPasswordVisible: Bool = false
    @FocusState private var isFocused: Bool

    public init(
        title: String,
        systemImage: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autoCapitalization: TextInputAutocapitalization = .never
    ) {
        self.title = title
        self.systemImage = systemImage
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autoCapitalization = autoCapitalization
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isFocused ? .primary : .secondary)
                .frame(width: 20)

            if isSecure && !isPasswordVisible {
                SecureField(title, text: $text)
                    .focused($isFocused)
                    .textContentType(UITesting.isActive ? nil : textContentType)
                    .textInputAutocapitalization(autoCapitalization)
            } else {
                TextField(title, text: $text)
                    .focused($isFocused)
                    .keyboardType(keyboardType)
                    .textContentType(UITesting.isActive ? nil : textContentType)
                    .textInputAutocapitalization(autoCapitalization)
                    .autocorrectionDisabled()
            }

            if isSecure {
                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else if !text.isEmpty && isFocused {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
