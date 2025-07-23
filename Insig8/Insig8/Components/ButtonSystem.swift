import SwiftUI

// MARK: - Enhanced Button Component
struct EnhancedButton: View {
    let text: String?
    let icon: String?
    let style: Style
    let size: Size
    let loading: Bool
    let disabled: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    enum Style {
        case primary, secondary, tertiary, destructive, ghost
    }
    
    enum Size {
        case small, medium, large
    }
    
    init(
        text: String? = nil,
        icon: String? = nil,
        style: Style = .primary,
        size: Size = .medium,
        loading: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.icon = icon
        self.style = style
        self.size = size
        self.loading = loading
        self.disabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: iconTextSpacing) {
                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(loadingScale)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(iconFont)
                }
                
                if let text = text {
                    Text(text)
                        .font(textFont)
                        .fontWeight(fontWeight)
                }
            }
            .foregroundColor(foregroundColor)
            .frame(minHeight: minHeight)
            .padding(paddingValue)
            .background(backgroundColor)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.quick) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(DesignTokens.Animation.quick) {
                isPressed = pressing
            }
        }, perform: {})
    }
    
    // MARK: - Style Computed Properties
    private var backgroundColor: Color {
        let baseColor: Color
        
        switch style {
        case .primary:
            baseColor = DesignTokens.Colors.primary
        case .secondary:
            baseColor = DesignTokens.Colors.surface
        case .tertiary:
            baseColor = DesignTokens.Colors.surfaceSecondary
        case .destructive:
            baseColor = DesignTokens.Colors.error
        case .ghost:
            return isHovered ? DesignTokens.Colors.hover : Color.clear
        }
        
        if isHovered && style != .ghost {
            return baseColor.opacity(0.9)
        }
        
        return baseColor
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return Color.white
        case .secondary, .tertiary, .ghost:
            return DesignTokens.Colors.onSurface
        }
    }
    
    private var borderOverlay: some View {
        Group {
            if style == .secondary || style == .tertiary {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DesignTokens.Colors.surfaceVariant, lineWidth: 1)
            }
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .small:
            return DesignTokens.Radius.sm
        case .medium:
            return DesignTokens.Radius.md
        case .large:
            return DesignTokens.Radius.lg
        }
    }
    
    private var paddingValue: EdgeInsets {
        switch size {
        case .small:
            return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        case .medium:
            return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        case .large:
            return EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        }
    }
    
    private var minHeight: CGFloat {
        switch size {
        case .small: return 28
        case .medium: return 36
        case .large: return 44
        }
    }
    
    private var textFont: Font {
        switch size {
        case .small:
            return DesignTokens.Typography.footnote
        case .medium:
            return DesignTokens.Typography.body
        case .large:
            return DesignTokens.Typography.callout
        }
    }
    
    private var fontWeight: Font.Weight {
        switch style {
        case .primary, .destructive:
            return .semibold
        case .secondary:
            return .medium
        case .tertiary, .ghost:
            return .regular
        }
    }
    
    private var iconFont: Font {
        switch size {
        case .small:
            return .caption
        case .medium:
            return .body
        case .large:
            return .callout
        }
    }
    
    private var iconTextSpacing: CGFloat {
        switch size {
        case .small: return DesignTokens.Spacing.xs
        case .medium: return DesignTokens.Spacing.sm
        case .large: return DesignTokens.Spacing.md
        }
    }
    
    private var loadingScale: CGFloat {
        switch size {
        case .small: return 0.7
        case .medium: return 0.8
        case .large: return 0.9
        }
    }
}

// MARK: - Icon Button
struct IconButton: View {
    let icon: String
    let style: Style
    let size: Size
    let loading: Bool
    let disabled: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    enum Style {
        case primary, secondary, ghost
    }
    
    enum Size {
        case small, medium, large
    }
    
    init(
        icon: String,
        style: Style = .secondary,
        size: Size = .medium,
        loading: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.size = size
        self.loading = loading
        self.disabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                        .font(iconFont)
                }
            }
            .foregroundColor(foregroundColor)
            .frame(width: buttonSize, height: buttonSize)
            .background(backgroundColor)
            .clipShape(Circle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.quick) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(DesignTokens.Animation.quick) {
                isPressed = pressing
            }
        }, perform: {})
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? DesignTokens.Colors.primary.opacity(0.9) : DesignTokens.Colors.primary
        case .secondary:
            return isHovered ? DesignTokens.Colors.surfaceVariant : DesignTokens.Colors.surface
        case .ghost:
            return isHovered ? DesignTokens.Colors.hover : Color.clear
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return Color.white
        case .secondary, .ghost:
            return DesignTokens.Colors.onSurface
        }
    }
    
    private var buttonSize: CGFloat {
        switch size {
        case .small: return 28
        case .medium: return 36
        case .large: return 44
        }
    }
    
    private var iconFont: Font {
        switch size {
        case .small: return .caption
        case .medium: return .body
        case .large: return .title3
        }
    }
}

// MARK: - Toggle Button
struct ToggleButton: View {
    @Binding var isOn: Bool
    let text: String?
    let icon: String?
    let style: Style
    let size: Size
    
    enum Style {
        case checkbox, switch_, segmented
    }
    
    enum Size {
        case small, medium, large
    }
    
    init(
        isOn: Binding<Bool>,
        text: String? = nil,
        icon: String? = nil,
        style: Style = .checkbox,
        size: Size = .medium
    ) {
        self._isOn = isOn
        self.text = text
        self.icon = icon
        self.style = style
        self.size = size
    }
    
    var body: some View {
        Button {
            withAnimation(DesignTokens.Animation.quick) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                toggleIndicator
                
                if let text = text {
                    Text(text)
                        .font(textFont)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(iconFont)
                        .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
    
    @ViewBuilder
    private var toggleIndicator: some View {
        switch style {
        case .checkbox:
            checkboxIndicator
        case .switch_:
            switchIndicator
        case .segmented:
            segmentedIndicator
        }
    }
    
    private var checkboxIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .stroke(
                    isOn ? DesignTokens.Colors.primary : DesignTokens.Colors.surfaceVariant,
                    lineWidth: 2
                )
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(isOn ? DesignTokens.Colors.primary : Color.clear)
                )
                .frame(width: checkboxSize, height: checkboxSize)
            
            if isOn {
                Image(systemName: "checkmark")
                    .font(checkmarkFont)
                    .foregroundColor(.white)
            }
        }
    }
    
    private var switchIndicator: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? DesignTokens.Colors.primary : DesignTokens.Colors.surfaceVariant)
                .frame(width: switchWidth, height: switchHeight)
            
            Circle()
                .fill(Color.white)
                .frame(width: switchKnobSize, height: switchKnobSize)
                .padding(2)
        }
    }
    
    private var segmentedIndicator: some View {
        Circle()
            .fill(isOn ? DesignTokens.Colors.primary : DesignTokens.Colors.surfaceVariant)
            .frame(width: radioSize, height: radioSize)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: radioSize * 0.5, height: radioSize * 0.5)
                    .opacity(isOn ? 1 : 0)
            )
    }
    
    // Size-dependent properties
    private var textFont: Font {
        switch size {
        case .small: return DesignTokens.Typography.footnote
        case .medium: return DesignTokens.Typography.body
        case .large: return DesignTokens.Typography.callout
        }
    }
    
    private var iconFont: Font {
        switch size {
        case .small: return .caption
        case .medium: return .body
        case .large: return .title3
        }
    }
    
    private var checkboxSize: CGFloat {
        switch size {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }
    
    private var checkmarkFont: Font {
        switch size {
        case .small: return .system(size: 10, weight: .bold)
        case .medium: return .system(size: 12, weight: .bold)
        case .large: return .system(size: 14, weight: .bold)
        }
    }
    
    private var switchWidth: CGFloat {
        switch size {
        case .small: return 32
        case .medium: return 40
        case .large: return 48
        }
    }
    
    private var switchHeight: CGFloat {
        switch size {
        case .small: return 18
        case .medium: return 22
        case .large: return 26
        }
    }
    
    private var switchKnobSize: CGFloat {
        switchHeight - 4
    }
    
    private var radioSize: CGFloat {
        checkboxSize
    }
}

// MARK: - Button Group
struct ButtonGroup<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    
    init(
        spacing: CGFloat = DesignTokens.Spacing.sm,
        alignment: HorizontalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.spacing = spacing
        self.alignment = alignment
    }
    
    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
        }
    }
}

#Preview("Button System") {
    VStack(spacing: DesignTokens.Spacing.lg) {
        // Enhanced buttons
        HStack {
            EnhancedButton(text: "Primary", style: .primary, action: {})
            EnhancedButton(text: "Secondary", style: .secondary, action: {})
            EnhancedButton(text: "Ghost", style: .ghost, action: {})
        }
        
        // Icon buttons
        HStack {
            IconButton(icon: "heart.fill", style: .primary, action: {})
            IconButton(icon: "star", style: .secondary, action: {})
            IconButton(icon: "trash", style: .ghost, action: {})
        }
        
        // Toggle buttons
        VStack {
            ToggleButton(isOn: .constant(true), text: "Checkbox", style: .checkbox)
            ToggleButton(isOn: .constant(false), text: "Switch", style: .switch_)
            ToggleButton(isOn: .constant(true), text: "Radio", style: .segmented)
        }
        
        // Loading states
        HStack {
            EnhancedButton(text: "Loading", style: .primary, loading: true, action: {})
            IconButton(icon: "heart", style: .secondary, loading: true, action: {})
        }
    }
    .padding()
}