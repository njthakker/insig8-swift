import SwiftUI
import AppKit
import Combine

class PanelManager: NSObject, ObservableObject {
    static let shared = PanelManager()
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    let appStore = AppStore() // Make this accessible for menu actions
    
    let objectWillChange = PassthroughSubject<Void, Never>()
    
    // Panel configuration
    private let panelWidth: CGFloat = 800
    private let panelHeight: CGFloat = 600
    
    override init() {
        super.init()
        setupPanel()
    }
    
    private func setupPanel() {
        // Create the SwiftUI view
        let contentView = ContentView()
            .environmentObject(appStore)
        
        hostingView = NSHostingView(rootView: AnyView(contentView))
        
        // Create the panel with proper configuration
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        guard let panel = panel else { return }
        
        // Configure panel behavior
        panel.level = .floating // Stay above other windows
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false  // Allow panel to become key
        panel.hidesOnDeactivate = false
        
        // Set up visual effects
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        
        // Add blur background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        
        panel.contentView = visualEffectView
        
        // Add the SwiftUI content
        if let hostingView = hostingView {
            visualEffectView.addSubview(hostingView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            
            // Use proper Auto Layout constraints
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
            ])
        }
        
        // Set delegate for auto-hide behavior
        panel.delegate = self
        
        // Initially hide the panel
        panel.orderOut(nil)
    }
    
    func showWindow() {
        guard let panel = panel else {
            print("Panel is nil!")
            return
        }
        
        print("Showing window...")
        
        // Position the panel on the appropriate screen
        positionPanel()
        
        // Show and activate the panel
        panel.makeKeyAndOrderFront(nil)
        
        // Force the app to become active
        NSApp.activate(ignoringOtherApps: true)
        
        // Make sure the panel becomes key window and focus search field
        DispatchQueue.main.async {
            panel.makeKey()
            // Post notification to focus search field
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        }
        
        print("Window should be visible now. Is visible: \(panel.isVisible)")
        print("Panel frame: \(panel.frame)")
        print("Panel level: \(panel.level.rawValue)")
    }
    
    func hideWindow() {
        guard let panel = panel else { return }
        print("Hiding window...")
        panel.orderOut(nil)
    }
    
    func toggleWindow() {
        guard let panel = panel else {
            print("Panel is nil in toggle!")
            return
        }
        
        print("Toggling window. Currently visible: \(panel.isVisible)")
        
        if panel.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    private func positionPanel() {
        guard let panel = panel else { return }
        
        // Get the screen with the mouse cursor (like the original app)
        let screen = getScreenWithMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }
        
        // Calculate position (centered horizontally, 30% from top like original)
        let yOffset = screen.visibleFrame.height * 0.3
        let x = screen.visibleFrame.midX - panelWidth / 2
        let y = screen.visibleFrame.midY - panelHeight / 2 + yOffset
        
        let newFrame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        panel.setFrame(newFrame, display: true)
    }
    
    private func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }
}

// MARK: - NSWindowDelegate
extension PanelManager: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Auto-hide when the panel loses focus (like the original app)
        DispatchQueue.main.async {
            self.hideWindow()
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Don't actually close, just hide
        hideWindow()
        return false
    }
}