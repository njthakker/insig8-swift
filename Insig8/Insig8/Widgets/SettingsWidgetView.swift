import SwiftUI
import ServiceManagement
import AppKit

struct SettingsWidgetView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.themeManager) private var themeManager
    @State private var showingPreferences = false
    
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(DesignTokens.Colors.primary)
                
                Text("Settings")
                    .font(DesignTokens.Typography.headline)
                
                Spacer()
                
                EnhancedButton(
                    text: "Open Preferences",
                    style: .secondary
                ) {
                    showingPreferences = true
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.md)
            
            // Quick Settings
            VStack(spacing: DesignTokens.Spacing.md) {
                SettingsRow(
                    icon: "moon.stars",
                    title: "Theme",
                    description: "Appearance settings"
                ) {
                    ThemePicker()
                }
                
                SettingsRow(
                    icon: "keyboard",
                    title: "Global Hotkey",
                    description: "⌘ Space"
                ) {
                    EnhancedButton(
                        text: "Change",
                        style: .tertiary
                    ) {
                        showingPreferences = true
                    }
                }
                
                SettingsRow(
                    icon: "app.badge",
                    title: "Show in Dock",
                    description: "Visibility settings"
                ) {
                    Toggle("", isOn: $appStore.showInDock)
                        .onChange(of: appStore.showInDock) { _, newValue in
                            updateDockVisibility(newValue)
                        }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            
            Spacer()
            
            // Footer
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("Version 2.0.0")
                    .font(DesignTokens.Typography.caption1)
                    .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
                
                HStack(spacing: DesignTokens.Spacing.md) {
                    Link("GitHub", destination: URL(string: "https://github.com/yourusername/insig8")!)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(DesignTokens.Colors.primary)
                    
                    Text("•")
                        .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
                    
                    Link("Support", destination: URL(string: "https://github.com/yourusername/insig8/issues")!)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(DesignTokens.Colors.primary)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardLayout()
        .sheet(isPresented: $showingPreferences) {
            PreferencesWindow()
        }
    }
    
    private func updateDockVisibility(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        UserDefaults.standard.set(visible, forKey: "showInDock")
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder let trailing: () -> Trailing
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(DesignTokens.Colors.primary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                
                Text(description)
                    .font(DesignTokens.Typography.caption1)
                    .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
            }
            
            Spacer()
            
            trailing()
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surfaceVariant.opacity(0.5))
        )
        .hoverAnimation()
    }
}

// MARK: - Preferences Window
struct PreferencesWindow: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            // Sidebar
            VStack(spacing: 0) {
                PreferencesSidebarItem(icon: "gear", title: "General", isSelected: true)
                PreferencesSidebarItem(icon: "paintbrush", title: "Appearance", isSelected: false)
                PreferencesSidebarItem(icon: "keyboard", title: "Shortcuts", isSelected: false)
                PreferencesSidebarItem(icon: "info.circle", title: "About", isSelected: false)
                Spacer()
            }
            .frame(width: 180)
            .background(DesignTokens.Colors.surfaceSecondary)
            
            // Content
            GeneralPreferencesView()
        }
        .frame(width: 600, height: 450)
        .background(DesignTokens.Colors.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .navigationTitle("Preferences")
    }
}

struct PreferencesSidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 16, height: 16)
            
            Text(title)
                .font(DesignTokens.Typography.body)
            
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .foregroundColor(isSelected ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurface)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(isSelected ? DesignTokens.Colors.primary.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            // Handle selection
        }
    }
}

struct GeneralPreferencesView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // General Settings
                PreferencesSection(title: "General") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        PreferencesToggleRow(
                            title: "Launch at login",
                            description: "Start Insig8 when you log in",
                            isOn: $appStore.launchAtLogin
                        )
                        .onChange(of: appStore.launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(newValue)
                        }
                        
                        PreferencesToggleRow(
                            title: "Show in Dock",
                            description: "Display app icon in the Dock",
                            isOn: $appStore.showInDock
                        )
                        .onChange(of: appStore.showInDock) { _, newValue in
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                            UserDefaults.standard.set(newValue, forKey: "showInDock")
                        }
                        
                        PreferencesToggleRow(
                            title: "File indexing",
                            description: "Index files for faster search",
                            isOn: $appStore.enableIndexing
                        )
                        .onChange(of: appStore.enableIndexing) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "enableIndexing")
                        }
                    }
                }
                
                // Search Settings
                PreferencesSection(title: "Search") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        PreferencesSliderRow(
                            title: "Search depth",
                            description: "How deep to search in directories",
                            value: $appStore.searchDepth,
                            range: 1...5
                        )
                        .onChange(of: appStore.searchDepth) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "searchDepth")
                        }
                        
                        PreferencesToggleRow(
                            title: "Calculator",
                            description: "Enable calculator expressions",
                            isOn: $appStore.enableCalculator
                        )
                        .onChange(of: appStore.enableCalculator) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "enableCalculator")
                        }
                        
                        PreferencesToggleRow(
                            title: "Web search suggestions",
                            description: "Show web search options",
                            isOn: $appStore.enableWebSearch
                        )
                        .onChange(of: appStore.enableWebSearch) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "enableWebSearch")
                        }
                    }
                }
                
                // Clipboard Settings
                PreferencesSection(title: "Clipboard") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        PreferencesPickerRow(
                            title: "History limit",
                            description: "Maximum clipboard items to remember",
                            selection: $appStore.clipboardLimit,
                            options: [50, 100, 200, 500, 1000]
                        )
                        .onChange(of: appStore.clipboardLimit) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "clipboardLimit")
                        }
                        
                        HStack {
                            EnhancedButton(
                                text: "Clear Clipboard History",
                                style: .secondary
                            ) {
                                clearClipboardHistory()
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
    }
    
    private func clearClipboardHistory() {
        // TODO: Implement clipboard history clearing
        print("Clearing clipboard history...")
    }
}

// Legacy settings views for TabView (keeping for backward compatibility)
struct SettingsView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var launchAtLogin = false
    @State private var showInDock = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        // Implement launch at login
                    }
                
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { oldValue, newValue in
                        // Update dock visibility
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        UserDefaults.standard.set(newValue, forKey: "showInDock")
                    }
            }
            
            Section("Clipboard") {
                HStack {
                    Text("History limit:")
                    Menu("100") {
                        Button("50") { }
                        Button("100") { }
                        Button("200") { }
                        Button("500") { }
                    }
                    .frame(width: 100)
                }
                
                Button("Clear Clipboard History") {
                    // Clear clipboard history
                }
            }
        }
        .padding(20)
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Theme:")
                    Menu("System") {
                        Button("System") { appStore.theme = .system }
                        Button("Light") { appStore.theme = .light }
                        Button("Dark") { appStore.theme = .dark }
                    }
                }
            }
            
            Section("Window") {
                HStack {
                    Text("Window width:")
                    Slider(value: .constant(800), in: 600...1200)
                    Text("800")
                        .monospacedDigit()
                }
                
                Toggle("Always on top", isOn: .constant(false))
            }
        }
        .padding(20)
    }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Global Shortcuts")
                .font(.headline)
            
            HStack {
                Text("Show/Hide window:")
                Spacer()
                ShortcutRecorder()
            }
            
            Divider()
            
            Text("In-App Shortcuts")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                ShortcutRow(action: "Navigate up", shortcut: "↑")
                ShortcutRow(action: "Navigate down", shortcut: "↓")
                ShortcutRow(action: "Select item", shortcut: "Return")
                ShortcutRow(action: "Cancel", shortcut: "Escape")
                ShortcutRow(action: "Switch to Search", shortcut: "⌘1")
                ShortcutRow(action: "Switch to Calendar", shortcut: "⌘2")
                ShortcutRow(action: "Switch to Clipboard", shortcut: "⌘3")
                ShortcutRow(action: "Switch to Translation", shortcut: "⌘4")
            }
            
            Spacer()
        }
        .padding(20)
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String
    
    var body: some View {
        HStack {
            Text(action)
                .foregroundColor(.secondary)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
        }
    }
}

struct ShortcutRecorder: View {
    var body: some View {
        Text("⌘ Space")
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "command")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Insig8")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version 2.0.0")
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("A powerful command palette for macOS")
                .font(.body)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 10) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/yourusername/insig8")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/yourusername/insig8/issues")!)
                Link("Documentation", destination: URL(string: "https://github.com/yourusername/insig8/wiki")!)
            }
            
            Spacer()
            
            Text("Built with SwiftUI and ❤️")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preference Components
struct PreferencesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.headline)
                .foregroundColor(DesignTokens.Colors.onSurface)
            
            VStack(spacing: DesignTokens.Spacing.sm) {
                content()
            }
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(DesignTokens.Colors.surfaceVariant.opacity(0.5))
            )
        }
    }
}

struct PreferencesToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                
                Text(description)
                    .font(DesignTokens.Typography.caption1)
                    .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
        }
    }
}

struct PreferencesSliderRow: View {
    let title: String
    let description: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                    
                    Text(description)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
                }
                
                Spacer()
                
                Text("\(value)")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.Colors.primary)
                    .frame(minWidth: 30)
            }
            
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
    }
}

struct PreferencesPickerRow: View {
    let title: String
    let description: String
    @Binding var selection: Int
    let options: [Int]
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                
                Text(description)
                    .font(DesignTokens.Typography.caption1)
                    .foregroundColor(DesignTokens.Colors.onSurfaceSecondary)
            }
            
            Spacer()
            
            Menu("\(selection)") {
                ForEach(options, id: \.self) { option in
                    Button("\(option)") {
                        selection = option
                    }
                }
            }
            .foregroundColor(DesignTokens.Colors.primary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceVariant)
            )
            .frame(minWidth: 80)
        }
    }
}

#Preview("Settings Widget") {
    SettingsWidgetView()
        .environmentObject(AppStore())
        .themingEnabled()
        .frame(width: 400, height: 500)
}

#Preview("Preferences Window") {
    PreferencesWindow()
        .environmentObject(AppStore())
        .themingEnabled()
}