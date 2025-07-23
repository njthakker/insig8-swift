import SwiftUI
import AppKit
import Combine

// MARK: - Theme Manager
@MainActor
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .system
    @Published var effectiveTheme: EffectiveTheme = .light
    
    init() {
        updateEffectiveTheme()
        observeSystemThemeChanges()
    }
    
    private func observeSystemThemeChanges() {
        // Use appearance change notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateEffectiveTheme()
            }
        }
    }
    
    private func updateEffectiveTheme() {
        switch currentTheme {
        case .light:
            effectiveTheme = .light
        case .dark:
            effectiveTheme = .dark
        case .system:
            let isDarkMode = NSApplication.shared.effectiveAppearance.name == .darkAqua
            effectiveTheme = isDarkMode ? .dark : .light
        }
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        updateEffectiveTheme()
        
        // Apply system appearance
        switch theme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }
}

// MARK: - Theme Types
enum AppTheme: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "gear"
        }
    }
}

enum EffectiveTheme {
    case light, dark
}

// MARK: - Themed Design Tokens
struct ThemedColors {
    let light: ColorScheme
    let dark: ColorScheme
    
    struct ColorScheme {
        // Primary colors
        let primary: Color
        let primaryVariant: Color
        let onPrimary: Color
        
        // Surface colors
        let surface: Color
        let surfaceSecondary: Color
        let surfaceVariant: Color
        let onSurface: Color
        let onSurfaceSecondary: Color
        let onSurfaceVariant: Color
        
        // Interactive states
        let hover: Color
        let pressed: Color
        let focused: Color
        let selected: Color
        
        // Semantic colors
        let success: Color
        let warning: Color
        let error: Color
        let info: Color
        
        // Effects
        let blur: Color
        let shadow: Color
        let border: Color
    }
    
    static let `default` = ThemedColors(
        light: ColorScheme(
            primary: Color(red: 0.0, green: 0.48, blue: 1.0),
            primaryVariant: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.8),
            onPrimary: .white,
            
            surface: Color(NSColor.controlBackgroundColor),
            surfaceSecondary: Color(NSColor.windowBackgroundColor),
            surfaceVariant: Color(red: 0.96, green: 0.96, blue: 0.96),
            onSurface: Color(NSColor.labelColor),
            onSurfaceSecondary: Color(NSColor.secondaryLabelColor),
            onSurfaceVariant: Color(NSColor.tertiaryLabelColor),
            
            hover: Color.black.opacity(0.05),
            pressed: Color.black.opacity(0.1),
            focused: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.2),
            selected: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.15),
            
            success: Color(red: 0.2, green: 0.78, blue: 0.35),
            warning: Color(red: 1.0, green: 0.58, blue: 0.0),
            error: Color(red: 1.0, green: 0.23, blue: 0.19),
            info: Color(red: 0.0, green: 0.48, blue: 1.0),
            
            blur: Color.white.opacity(0.8),
            shadow: Color.black.opacity(0.1),
            border: Color.black.opacity(0.1)
        ),
        dark: ColorScheme(
            primary: Color(red: 0.39, green: 0.7, blue: 1.0),
            primaryVariant: Color(red: 0.39, green: 0.7, blue: 1.0).opacity(0.8),
            onPrimary: Color.black,
            
            surface: Color(NSColor.controlBackgroundColor),
            surfaceSecondary: Color(NSColor.windowBackgroundColor),
            surfaceVariant: Color(red: 0.15, green: 0.15, blue: 0.15),
            onSurface: Color(NSColor.labelColor),
            onSurfaceSecondary: Color(NSColor.secondaryLabelColor),
            onSurfaceVariant: Color(NSColor.tertiaryLabelColor),
            
            hover: Color.white.opacity(0.05),
            pressed: Color.white.opacity(0.1),
            focused: Color(red: 0.39, green: 0.7, blue: 1.0).opacity(0.2),
            selected: Color(red: 0.39, green: 0.7, blue: 1.0).opacity(0.15),
            
            success: Color(red: 0.3, green: 0.85, blue: 0.4),
            warning: Color(red: 1.0, green: 0.65, blue: 0.1),
            error: Color(red: 1.0, green: 0.34, blue: 0.34),
            info: Color(red: 0.39, green: 0.7, blue: 1.0),
            
            blur: Color.black.opacity(0.8),
            shadow: Color.black.opacity(0.3),
            border: Color.white.opacity(0.1)
        )
    )
    
    func colors(for theme: EffectiveTheme) -> ColorScheme {
        switch theme {
        case .light: return light
        case .dark: return dark
        }
    }
}

// MARK: - Theme Environment
private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager? = nil
}

extension EnvironmentValues {
    var themeManager: ThemeManager? {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

// MARK: - Themed Design System
extension DesignTokens {
    struct ThemedDesignTokens {
        let colors: ThemedColors.ColorScheme
        let theme: EffectiveTheme
        
        init(theme: EffectiveTheme) {
            self.theme = theme
            self.colors = ThemedColors.default.colors(for: theme)
        }
        
        // Semantic color helpers
        var backgroundPrimary: Color { colors.surface }
        var backgroundSecondary: Color { colors.surfaceSecondary }
        var textPrimary: Color { colors.onSurface }
        var textSecondary: Color { colors.onSurfaceSecondary }
        var accent: Color { colors.primary }
        
        // Interactive state colors
        var interactiveHover: Color { colors.hover }
        var interactivePressed: Color { colors.pressed }
        var interactiveFocused: Color { colors.focused }
        
        // Status colors
        var statusSuccess: Color { colors.success }
        var statusWarning: Color { colors.warning }
        var statusError: Color { colors.error }
        var statusInfo: Color { colors.info }
    }
}

// MARK: - Theme-aware Components
struct ThemedView<Content: View>: View {
    @Environment(\.themeManager) private var themeManager
    let content: (DesignTokens.ThemedDesignTokens) -> Content
    
    init(@ViewBuilder content: @escaping (DesignTokens.ThemedDesignTokens) -> Content) {
        self.content = content
    }
    
    var body: some View {
        let theme = themeManager?.effectiveTheme ?? .light
        let tokens = DesignTokens.ThemedDesignTokens(theme: theme)
        content(tokens)
    }
}

// MARK: - Theme Picker Component
struct ThemePicker: View {
    @Environment(\.themeManager) private var themeManager
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                ThemeOptionButton(
                    theme: theme,
                    isSelected: themeManager?.currentTheme == theme
                ) {
                    themeManager?.setTheme(theme)
                }
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surfaceVariant)
        )
    }
}

private struct ThemeOptionButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: theme.icon)
                    .font(.caption)
                
                if isSelected {
                    Text(theme.displayName)
                        .font(DesignTokens.Typography.caption1)
                }
            }
            .foregroundColor(isSelected ? .white : DesignTokens.Colors.onSurface)
            .padding(.horizontal, isSelected ? DesignTokens.Spacing.sm : DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isSelected ? DesignTokens.Colors.primary : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.quick, value: isSelected)
    }
}

// MARK: - Theme Transition Effect
struct ThemeTransition: ViewModifier {
    @Environment(\.themeManager) private var themeManager
    
    func body(content: Content) -> some View {
        content
            .animation(DesignTokens.Animation.smooth, value: themeManager?.effectiveTheme)
    }
}

// MARK: - View Extensions
extension View {
    func themedView<Content: View>(@ViewBuilder content: @escaping (DesignTokens.ThemedDesignTokens) -> Content) -> some View {
        ThemedView(content: content)
    }
    
    func themeTransition() -> some View {
        modifier(ThemeTransition())
    }
    
    func themingEnabled() -> some View {
        environment(\.themeManager, ThemeManager())
    }
}

// MARK: - Adaptive Colors
struct AdaptiveColor {
    let light: Color
    let dark: Color
    
    func color(for theme: EffectiveTheme) -> Color {
        switch theme {
        case .light: return light
        case .dark: return dark
        }
    }
}

// MARK: - Color Extensions
extension Color {
    static func adaptive(light: Color, dark: Color) -> AdaptiveColor {
        AdaptiveColor(light: light, dark: dark)
    }
    
    // Common adaptive colors
    static let adaptiveBackground = adaptive(
        light: Color(NSColor.windowBackgroundColor),
        dark: Color(NSColor.windowBackgroundColor)
    )
    
    static let adaptiveText = adaptive(
        light: Color(NSColor.labelColor),
        dark: Color(NSColor.labelColor)
    )
    
    static let adaptiveBorder = adaptive(
        light: Color.black.opacity(0.1),
        dark: Color.white.opacity(0.1)
    )
}

#Preview("Theme System") {
    VStack(spacing: DesignTokens.Spacing.lg) {
        ThemePicker()
        
        ThemedView { tokens in
            VStack(spacing: DesignTokens.Spacing.md) {
                Text("Primary Background")
                    .padding()
                    .background(tokens.backgroundPrimary)
                    .foregroundColor(tokens.textPrimary)
                    .cornerRadius(DesignTokens.Radius.md)
                
                Text("Secondary Background")
                    .padding()
                    .background(tokens.backgroundSecondary)
                    .foregroundColor(tokens.textSecondary)
                    .cornerRadius(DesignTokens.Radius.md)
                
                HStack {
                    Rectangle()
                        .fill(tokens.statusSuccess)
                        .frame(height: 40)
                        .cornerRadius(DesignTokens.Radius.sm)
                    
                    Rectangle()
                        .fill(tokens.statusWarning)
                        .frame(height: 40)
                        .cornerRadius(DesignTokens.Radius.sm)
                    
                    Rectangle()
                        .fill(tokens.statusError)
                        .frame(height: 40)
                        .cornerRadius(DesignTokens.Radius.sm)
                    
                    Rectangle()
                        .fill(tokens.accent)
                        .frame(height: 40)
                        .cornerRadius(DesignTokens.Radius.sm)
                }
            }
        }
    }
    .padding()
    .themingEnabled()
}