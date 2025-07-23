//
//  AppFocusMonitor.swift
//  Insig8
//
//  Service to monitor app focus changes and coordinate monitoring services
//

import Foundation
import AppKit
import Combine
import os.log

@MainActor
class AppFocusMonitor: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Insig8", category: "AppFocusMonitor")
    
    @Published var currentApp: String?
    @Published var isMonitoringActive: Bool = false
    
    // Apps selected for monitoring
    @Published var monitoredApps: Set<String> = [
        "Slack", "Microsoft Teams", "Discord", "Mail", "Messages", 
        "Zoom", "Google Meet", "Safari", "Google Chrome", "Xcode"
    ]
    
    private var focusTimer: Timer?
    private let appStore: AppStore
    
    init(appStore: AppStore) {
        self.appStore = appStore
    }
    
    func startMonitoring() {
        // Monitor active app changes every 2 seconds
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await self.checkCurrentApp()
            }
        }
        
        logger.info("Started app focus monitoring")
    }
    
    func stopMonitoring() {
        focusTimer?.invalidate()
        focusTimer = nil
        
        // Stop all monitoring services
        Task {
            await stopAllMonitoring()
        }
        
        logger.info("Stopped app focus monitoring")
    }
    
    private func checkCurrentApp() async {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        
        // Only act if app changed
        guard appName != currentApp else { return }
        
        let previousApp = currentApp
        currentApp = appName
        
        logger.debug("App focus changed: \(previousApp ?? "None") -> \(appName)")
        
        // Check if new app should be monitored
        let shouldMonitor = monitoredApps.contains(appName) && appStore.enableAIMonitoring
        
        if shouldMonitor && !isMonitoringActive {
            await startMonitoringForApp(appName)
        } else if !shouldMonitor && isMonitoringActive {
            await stopAllMonitoring()
        }
    }
    
    private func startMonitoringForApp(_ appName: String) async {
        logger.info("Starting monitoring for app: \(appName)")
        
        // Start screen monitoring if enabled
        if appStore.monitorScreenContent {
            do {
                try await appStore.screenCapture.startMonitoring()
                logger.info("✅ Screen monitoring started for \(appName)")
            } catch {
                logger.error("❌ Failed to start screen monitoring: \(error)")
            }
        }
        
        // Start audio monitoring if enabled (placeholder for now)
        if appStore.monitorAudioTranscripts {
            // TODO: Implement audio monitoring service
            logger.info("📱 Audio monitoring would start for \(appName)")
        }
        
        // Start keyboard monitoring if enabled (placeholder for now)
        if appStore.monitorKeyboardInput {
            // TODO: Implement keyboard monitoring service
            logger.info("⌨️ Keyboard monitoring would start for \(appName)")
        }
        
        isMonitoringActive = true
    }
    
    private func stopAllMonitoring() async {
        logger.info("Stopping all monitoring services")
        
        // Stop screen monitoring
        await appStore.screenCapture.stopMonitoring()
        
        // TODO: Stop audio and keyboard monitoring when implemented
        
        isMonitoringActive = false
    }
    
    // MARK: - Configuration
    
    func addMonitoredApp(_ appName: String) {
        monitoredApps.insert(appName)
        UserDefaults.standard.set(Array(monitoredApps), forKey: "monitoredApps")
        logger.info("Added \(appName) to monitored apps")
    }
    
    func removeMonitoredApp(_ appName: String) {
        monitoredApps.remove(appName)
        UserDefaults.standard.set(Array(monitoredApps), forKey: "monitoredApps")
        logger.info("Removed \(appName) from monitored apps")
        
        // Stop monitoring if current app was removed
        if currentApp == appName && isMonitoringActive {
            Task {
                await stopAllMonitoring()
            }
        }
    }
    
    func loadMonitoredApps() {
        if let savedApps = UserDefaults.standard.array(forKey: "monitoredApps") as? [String] {
            monitoredApps = Set(savedApps)
        }
    }
    
    // MARK: - Status
    
    func getMonitoringStatus() -> String {
        if let currentApp = currentApp {
            if isMonitoringActive {
                return "Monitoring \(currentApp)"
            } else {
                return "Focused on \(currentApp) (not monitored)"
            }
        } else {
            return "No app focused"
        }
    }
}

// MARK: - Supporting Types

struct MonitoringStatus {
    let isActive: Bool
    let currentApp: String?
    let monitoredApps: Set<String>
    let enabledServices: [String]
}