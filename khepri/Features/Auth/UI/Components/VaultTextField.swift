import NorthKit
import SwiftUI

public struct VaultTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autoCapitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .return
    var focus: FocusState<Bool>.Binding?
    var onSubmit: () -> Void = {}

    @State private var isPasswordVisible: Bool = false
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 20

    /// - Parameters:
    ///   - focus: Lets the form move the keyboard here, for a Return key that goes to the next field.
    ///   - onSubmit: Runs when Return is pressed in this field.
    public init(
        title: String,
        systemImage: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autoCapitalization: TextInputAutocapitalization = .never,
        submitLabel: SubmitLabel = .return,
        focus: FocusState<Bool>.Binding? = nil,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.title = title
        self.systemImage = systemImage
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autoCapitalization = autoCapitalization
        self.submitLabel = submitLabel
        self.focus = focus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            if isSecure && !isPasswordVisible {
                SecureField(title, text: $text)
                    .focused($isFocused)
                    .modifier(FormFocus(binding: focus))
                    .textContentType(UITesting.isActive ? nil : textContentType)
                    .textInputAutocapitalization(autoCapitalization)
            } else {
                TextField(title, text: $text)
                    .focused($isFocused)
                    .modifier(FormFocus(binding: focus))
                    .keyboardType(keyboardType)
                    .textContentType(UITesting.isActive ? nil : textContentType)
                    .textInputAutocapitalization(autoCapitalization)
                    .autocorrectionDisabled()
            }

            if isSecure {
                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .trailingAccessoryHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? Text("Hide password") : Text("Show password"))
            } else if !text.isEmpty && isFocused {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .trailingAccessoryHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: NorthRadius.control, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NorthRadius.control, style: .continuous)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .submitLabel(submitLabel)
        .onSubmit(onSubmit)
    }
}

private struct FormFocus: ViewModifier {
    let binding: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let binding { content.focused(binding) } else { content }
    }
}

private extension View {
    /// Grows a small trailing glyph's touch area to 44 pt without growing the field.
    func trailingAccessoryHitArea() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .padding(.vertical, -12)
            .padding(.horizontal, -12)
    }
}
