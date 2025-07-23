import SwiftUI
import Combine

extension Notification.Name {
    static let focusSearchField = Notification.Name("focusSearchField")
}

// MARK: - Enhanced Input Component
struct EnhancedInput: View {
    @Binding var text: String
    let placeholder: String
    let style: Style
    let validation: Validation?
    let leadingIcon: String?
    let trailingIcon: String?
    let onTrailingIconTap: (() -> Void)?
    let onSubmit: (() -> Void)?
    
    @FocusState private var isFocused: Bool
    @State private var showValidation = false
    @State private var validationMessage = ""
    
    enum Style {
        case primary, secondary, search, minimal
    }
    
    struct Validation {
        let rules: [(String) -> String?]
        let validateOnChange: Bool
        
        init(_ rules: @escaping (String) -> String?, validateOnChange: Bool = false) {
            self.rules = [rules]
            self.validateOnChange = validateOnChange
        }
        
        init(_ rules: [(String) -> String?], validateOnChange: Bool = false) {
            self.rules = rules
            self.validateOnChange = validateOnChange
        }
    }
    
    init(
        text: Binding<String>,
        placeholder: String,
        style: Style = .primary,
        validation: Validation? = nil,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        onTrailingIconTap: (() -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.style = style
        self.validation = validation
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.onTrailingIconTap = onTrailingIconTap
        self.onSubmit = onSubmit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            inputField
            
            if showValidation && !validationMessage.isEmpty {
                validationText
            }
        }
    }
    
    private var inputField: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Leading icon
            if let leadingIcon = leadingIcon {
                Image(systemName: leadingIcon)
                    .font(iconFont)
                    .foregroundColor(iconColor)
                    .frame(width: 20)
            }
            
            // Text field
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(textFont)
                .focused($isFocused)
                .onSubmit {
                    validateInput()
                    onSubmit?()
                }
                .onChange(of: text) { oldValue, newValue in
                    if validation?.validateOnChange == true {
                        validateInput()
                    }
                }
            
            // Trailing icon or clear button
            if let trailingIcon = trailingIcon {
                Button(action: { onTrailingIconTap?() }) {
                    Image(systemName: trailingIcon)
                        .font(iconFont)
                        .foregroundColor(iconColor)
                }
                .buttonStyle(.plain)
                .hoverEffect()
            } else if !text.isEmpty && isFocused {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(iconFont)
                        .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .padding(paddingValue)
        .background(backgroundColor)
        .overlay(borderOverlay)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(DesignTokens.Animation.quick, value: isFocused)
        .animation(DesignTokens.Animation.quick, value: text.isEmpty)
    }
    
    private var validationText: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(DesignTokens.Colors.error)
            
            Text(validationMessage)
                .font(DesignTokens.Typography.caption2)
                .foregroundColor(DesignTokens.Colors.error)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Style Computed Properties
    private var backgroundColor: Color {
        switch style {
        case .primary, .secondary:
            return isFocused ? DesignTokens.Colors.surface : DesignTokens.Colors.surfaceSecondary
        case .search:
            return DesignTokens.Colors.surface
        case .minimal:
            return Color.clear
        }
    }
    
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(borderColor, lineWidth: borderWidth)
    }
    
    private var borderColor: Color {
        if showValidation && !validationMessage.isEmpty {
            return DesignTokens.Colors.error
        } else if isFocused {
            return DesignTokens.Colors.primary
        } else {
            return DesignTokens.Colors.surfaceVariant
        }
    }
    
    private var borderWidth: CGFloat {
        switch style {
        case .primary, .search:
            return isFocused ? 2 : 1
        case .secondary:
            return 1
        case .minimal:
            return isFocused ? 1 : 0
        }
    }
    
    private var cornerRadius: CGFloat {
        switch style {
        case .primary, .secondary:
            return DesignTokens.Radius.md
        case .search:
            return DesignTokens.Radius.lg
        case .minimal:
            return DesignTokens.Radius.sm
        }
    }
    
    private var paddingValue: EdgeInsets {
        switch style {
        case .primary, .secondary:
            return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .search:
            return EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        case .minimal:
            return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        }
    }
    
    private var textFont: Font {
        switch style {
        case .search:
            return DesignTokens.Typography.title2
        case .primary, .secondary:
            return DesignTokens.Typography.body
        case .minimal:
            return DesignTokens.Typography.callout
        }
    }
    
    private var iconFont: Font {
        switch style {
        case .search:
            return .title3
        case .primary, .secondary:
            return .body
        case .minimal:
            return .callout
        }
    }
    
    private var iconColor: Color {
        if isFocused {
            return DesignTokens.Colors.primary
        } else {
            return DesignTokens.Colors.onSurfaceSecondary
        }
    }
    
    // MARK: - Validation Logic
    private func validateInput() {
        guard let validation = validation else {
            showValidation = false
            return
        }
        
        for rule in validation.rules {
            if let errorMessage = rule(text) {
                validationMessage = errorMessage
                showValidation = true
                return
            }
        }
        
        showValidation = false
        validationMessage = ""
    }
}

// MARK: - Common Validation Rules
extension EnhancedInput.Validation {
    static func required(message: String = "This field is required") -> EnhancedInput.Validation {
        EnhancedInput.Validation { text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? message : nil
        }
    }
    
    static func minLength(_ length: Int, message: String? = nil) -> EnhancedInput.Validation {
        EnhancedInput.Validation { text in
            text.count < length ? (message ?? "Must be at least \(length) characters") : nil
        }
    }
    
    static func maxLength(_ length: Int, message: String? = nil) -> EnhancedInput.Validation {
        EnhancedInput.Validation { text in
            text.count > length ? (message ?? "Must be no more than \(length) characters") : nil
        }
    }
    
    static func email(message: String = "Please enter a valid email") -> EnhancedInput.Validation {
        EnhancedInput.Validation { text in
            let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
            return predicate.evaluate(with: text) ? nil : message
        }
    }
}

// MARK: - Enhanced Search Input (Specialized)
struct EnhancedSearchInput: View {
    @Binding var text: String
    let placeholder: String
    let leadingIcon: String
    let suggestions: [String]
    let onSuggestionTap: ((String) -> Void)?
    let onSubmit: (() -> Void)?
    
    @FocusState var isFocused: Bool
    @State private var showSuggestions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnhancedInput(
                text: $text,
                placeholder: placeholder,
                style: .search,
                leadingIcon: leadingIcon,
                trailingIcon: showClearButton ? "xmark.circle.fill" : nil,
                onTrailingIconTap: { text = "" },
                onSubmit: onSubmit
            )
            .focused($isFocused)
            
            if showSuggestions && !filteredSuggestions.isEmpty {
                suggestionsList
            }
        }
        .onChange(of: text) { oldValue, newValue in
            showSuggestions = isFocused && !newValue.isEmpty
        }
        .onChange(of: isFocused) { oldValue, newValue in
            showSuggestions = newValue && !text.isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            isFocused = true
        }
    }
    
    private var showClearButton: Bool {
        !text.isEmpty && isFocused
    }
    
    private var filteredSuggestions: [String] {
        guard !text.isEmpty else { return [] }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(text) }
    }
    
    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredSuggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                SuggestionRow(
                    text: suggestion,
                    query: text,
                    onTap: {
                        text = suggestion
                        onSuggestionTap?(suggestion)
                        showSuggestions = false
                    }
                )
                
                if index < filteredSuggestions.prefix(5).count - 1 {
                    Divider()
                        .padding(.leading, DesignTokens.Spacing.lg)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surface)
        .cardStyle(.elevated)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Suggestion Row
struct SuggestionRow: View {
    let text: String
    let query: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                HighlightedText(text: text, highlight: query)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                
                Spacer()
                
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

// MARK: - Highlighted Text
struct HighlightedText: View {
    let text: String
    let highlight: String
    
    var body: some View {
        if highlight.isEmpty {
            Text(text)
        } else {
            Text(attributedString)
        }
    }
    
    private var attributedString: AttributedString {
        var attributed = AttributedString(text)
        
        if let range = attributed.range(of: highlight, options: .caseInsensitive) {
            attributed[range].foregroundColor = DesignTokens.Colors.primary
            attributed[range].font = DesignTokens.Typography.body.weight(.medium)
        }
        
        return attributed
    }
}

#Preview("Enhanced Input Styles") {
    VStack(spacing: DesignTokens.Spacing.lg) {
        EnhancedInput(
            text: .constant(""),
            placeholder: "Primary Input",
            style: .primary,
            leadingIcon: "magnifyingglass"
        )
        
        EnhancedInput(
            text: .constant(""),
            placeholder: "Search Input",
            style: .search,
            leadingIcon: "magnifyingglass"
        )
        
        EnhancedInput(
            text: .constant(""),
            placeholder: "Secondary Input",
            style: .secondary
        )
        
        EnhancedInput(
            text: .constant(""),
            placeholder: "Minimal Input",
            style: .minimal
        )
    }
    .padding()
}