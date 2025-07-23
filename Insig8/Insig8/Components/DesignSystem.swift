import SwiftUI

// MARK: - Design Tokens
struct DesignTokens {
    // MARK: - Colors
    struct Colors {
        // Primary palette
        static let primary = Color.accentColor
        static let primaryVariant = Color.accentColor.opacity(0.8)
        
        // Surface colors
        static let surface = Color(NSColor.controlBackgroundColor)
        static let surfaceSecondary = Color(NSColor.windowBackgroundColor)
        static let surfaceVariant = Color(NSColor.separatorColor).opacity(0.1)
        
        // Content colors
        static let onSurface = Color.primary
        static let onSurfaceSecondary = Color.secondary
        static let onSurfaceVariant = Color(NSColor.tertiaryLabelColor)
        
        // Interactive states
        static let hover = Color.primary.opacity(0.05)
        static let pressed = Color.primary.opacity(0.1)
        static let focused = Color.accentColor.opacity(0.2)
        static let selected = Color.accentColor.opacity(0.15)
        
        // Semantic colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // Blur and effects
        static let blur = Color.white.opacity(0.8)
        static let blurDark = Color.black.opacity(0.3)
    }
    
    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title1 = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.medium)
        static let title3 = Font.title3.weight(.medium)
        
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption1 = Font.caption
        static let caption2 = Font.caption2
        
        // Monospaced variants
        static let bodyMono = Font.body.monospaced()
        static let captionMono = Font.caption.monospaced()
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        
        // Semantic spacing
        static let componentPadding = md
        static let itemSpacing = sm
        static let sectionSpacing = lg
        static let screenPadding = xl
    }
    
    // MARK: - Border Radius
    struct Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let round: CGFloat = 999
    }
    
    // MARK: - Shadows
    struct Shadow {
        static let subtle = Color.black.opacity(0.05)
        static let medium = Color.black.opacity(0.1)
        static let elevated = Color.black.opacity(0.15)
    }
    
    // MARK: - Animation
    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.35)
        static let spring = SwiftUI.Animation.spring(dampingFraction: 0.8)
    }
}

// MARK: - Custom View Modifiers
struct CardStyle: ViewModifier {
    let variant: Variant
    
    enum Variant {
        case elevated, flat, outlined
    }
    
    func body(content: Content) -> some View {
        switch variant {
        case .elevated:
            content
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .shadow(color: DesignTokens.Shadow.medium, radius: 8, y: 4)
        case .flat:
            content
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        case .outlined:
            content
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(DesignTokens.Colors.surfaceVariant, lineWidth: 1)
                )
        }
    }
}

struct ShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: radius, x: x, y: y)
    }
}

struct StrokeModifier: ViewModifier {
    let color: Color
    let lineWidth: CGFloat
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .stroke(color, lineWidth: lineWidth)
            )
    }
}

struct HoverEffect: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isHovered ? DesignTokens.Colors.hover : Color.clear)
            )
            .onHover { hovering in
                withAnimation(DesignTokens.Animation.quick) {
                    isHovered = hovering
                }
            }
    }
}

struct PressEffect: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isPressed ? DesignTokens.Colors.pressed : Color.clear)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(DesignTokens.Animation.quick, value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

// MARK: - View Extensions
extension View {
    // Card styles
    func cardStyle(_ variant: CardStyle.Variant = .elevated) -> some View {
        modifier(CardStyle(variant: variant))
    }
    
    // Interactive effects
    func hoverEffect() -> some View {
        modifier(HoverEffect())
    }
    
    func pressEffect() -> some View {
        modifier(PressEffect())
    }
    
    // Shadows
    func elevatedShadow() -> some View {
        modifier(ShadowModifier(color: DesignTokens.Shadow.elevated, radius: 12, y: 6))
    }
    
    func subtleShadow() -> some View {
        modifier(ShadowModifier(color: DesignTokens.Shadow.subtle, radius: 4, y: 2))
    }
    
    // Animations
    func quickAnimation() -> some View {
        animation(DesignTokens.Animation.quick, value: UUID())
    }
    
    func smoothAnimation() -> some View {
        animation(DesignTokens.Animation.smooth, value: UUID())
    }
    
    func springAnimation() -> some View {
        animation(DesignTokens.Animation.spring, value: UUID())
    }
}

// MARK: - Empty Modifier Helper
struct EmptyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}