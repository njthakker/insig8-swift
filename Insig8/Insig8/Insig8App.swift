import SwiftUI
import AppKit

@main
struct Insig8App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appStore = AppStore.shared
    
    var body: some Scene {
        // Empty WindowGroup - we'll use custom NSPanel instead
        WindowGroup(id: "main") {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        
        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appStore)
        }
    }
}

// AppDelegate for advanced macOS features
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var globalHotKey: GlobalHotKey?
    var panelManager: PanelManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App delegate launching...")
        
        // Initialize panel manager first
        panelManager = PanelManager.shared
        print("Panel manager initialized: \(panelManager != nil)")
        
        // Set up menu bar item
        setupMenuBarItem()
        
        // Set up global hotkey
        setupGlobalHotKey()
        
        // Set activation policy - start as accessory (menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Close any SwiftUI windows that opened automatically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                if !(window is NSPanel) {
                    window.close()
                }
            }
        }
        
        print("App delegate launch complete")
    }
    
    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Insig8")
            
            // Set up button for both left and right clicks (don't assign menu directly)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            print("Menu bar item set up with click handlers")
        } else {
            print("Failed to get status item button")
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        print("Status item clicked with event type: \(event.type.rawValue)")
        
        if event.type == .rightMouseUp {
            // Right click - show menu
            let menu = createMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            // Left click - open command palette
            print("Left click detected - opening command palette")
            openCommandPalette()
        }
    }
    
    private func setupGlobalHotKey() {
        // Set up global hotkey (Command+Period like original app)
        globalHotKey = GlobalHotKey(keyCombo: KeyCombo(key: .period, modifiers: .command)) { [weak self] in
            self?.openCommandPalette()
        }
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // Command Palette option
        let commandPaletteItem = NSMenuItem(title: "Open Command Palette", action: #selector(openCommandPalette), keyEquivalent: "")
        commandPaletteItem.target = self
        menu.addItem(commandPaletteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick access widgets
        let calendarItem = NSMenuItem(title: "View Calendar Events", action: #selector(openCalendarWidget), keyEquivalent: "")
        calendarItem.target = self
        menu.addItem(calendarItem)
        
        let clipboardItem = NSMenuItem(title: "Clipboard History", action: #selector(openClipboardWidget), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettingsWidget), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // App controls
        let aboutItem = NSMenuItem(title: "About Insig8", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit Insig8", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func openCommandPalette() {
        if let pm = panelManager {
            pm.showWindow()
        }
    }
    
    @objc private func openCalendarWidget() {
        // Get the AppStore instance and switch to calendar widget
        if let appStore = panelManager?.appStore {
            appStore.switchToWidget(.calendar)
        }
        if let pm = panelManager {
            pm.showWindow()
        }
    }
    
    @objc private func openClipboardWidget() {
        if let appStore = panelManager?.appStore {
            appStore.switchToWidget(.clipboard)
        }
        if let pm = panelManager {
            pm.showWindow()
        }
    }
    
    @objc private func openSettingsWidget() {
        if let appStore = panelManager?.appStore {
            appStore.switchToWidget(.settings)
        }
        if let pm = panelManager {
            pm.showWindow()
        }
    }
    
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func updateDockIconVisibility() {
        // This will be controlled by user preference
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
    
    // Allow calendar service to temporarily become regular app for permission dialogs
    static func temporarilyShowInDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    static func hideFromDock() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // This is called when the user clicks the dock icon or uses Cmd+Tab
        if !flag {
            openCommandPalette()
        }
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // GlobalHotKey will unregister itself in deinit
        globalHotKey = nil
    }
}

// Visual effect background
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Update view if needed
    }
}