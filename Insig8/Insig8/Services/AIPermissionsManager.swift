//
//  AIPermissionsManager.swift
//  Insig8
//
//  Manages app-specific AI permissions and system permission requests
//

import Foundation
import SwiftUI
import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit
import os.log

@MainActor
class AIPermissionsManager: ObservableObject {
    static let shared = AIPermissionsManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Insig8", category: "Permissions")
    
    // Global permissions
    @Published var globalScreenPermission: Bool = false
    @Published var globalAudioPermission: Bool = false
    @Published var globalKeyboardPermission: Bool = false
    @Published var globalEmailPermission: Bool = true
    @Published var globalCalendarPermission: Bool = true
    
    // Data controls
    @Published var dataRetentionDays: Int = 30
    @Published var autoDeleteSensitive: Bool = true
    
    // Monitored apps
    @Published var monitoredApps: [MonitoredApp] = []
    
    // Statistics
    @Published var stats = PermissionStats()
    
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadPermissions()
        loadMonitoredApps()
        loadStats()
    }
    
    // MARK: - System Permission Requests
    
    func requestScreenRecordingPermission() {
        Task {
            // Check current permission status
            let hasPermission = await checkScreenRecordingPermission()
            
            if !hasPermission {
                // Open System Settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            await MainActor.run {
                globalScreenPermission = hasPermission
                savePermissions()
            }
        }
    }
    
    func requestMicrophonePermission() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                self.globalAudioPermission = granted
                self.savePermissions()
            }
        }
    }
    
    func requestAccessibilityPermission() {
        // Check if accessibility permission is granted
        let hasPermission = AXIsProcessTrusted()
        
        if !hasPermission {
            // Prompt user to grant accessibility permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
            let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        
        globalKeyboardPermission = hasPermission
        savePermissions()
    }
    
    private func checkScreenRecordingPermission() async -> Bool {
        // This is a simplified check - production would use proper ScreenCaptureKit APIs
        do {
            let _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - App Management
    
    func addMonitoredApp(_ appName: String, bundleURL: URL) {
        // Get app icon and bundle information
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        let bundle = Bundle(url: bundleURL)
        let bundleID = bundle?.bundleIdentifier
        
        let app = MonitoredApp(
            id: UUID(),
            name: appName,
            bundleID: bundleID,
            bundlePath: bundleURL.path,
            icon: icon,
            isEnabled: true,
            permissions: AppPermissions(
                screenCapture: globalScreenPermission,
                audioCapture: globalAudioPermission,
                keyboardMonitoring: globalKeyboardPermission
            ),
            addedDate: Date()
        )
        
        monitoredApps.append(app)
        saveMonitoredApps()
        
        logger.info("Added monitored app: \(appName)")
    }
    
    func removeMonitoredApp(_ appId: UUID) {
        monitoredApps.removeAll { $0.id == appId }
        saveMonitoredApps()
        
        logger.info("Removed monitored app with ID: \(appId)")
    }
    
    func updateAppPermissions(_ appId: UUID, permissions: AppPermissions) {
        if let index = monitoredApps.firstIndex(where: { $0.id == appId }) {
            monitoredApps[index].permissions = permissions
            saveMonitoredApps()
        }
    }
    
    func isAppMonitoringEnabled(_ appName: String) -> Bool {
        return monitoredApps.first { $0.name == appName }?.isEnabled ?? false
    }
    
    func getAppPermissions(_ appName: String) -> AppPermissions? {
        return monitoredApps.first { $0.name == appName }?.permissions
    }
    
    // MARK: - Data Management
    
    func clearAllData() {
        Task {
            // Clear from UserDefaults (simplified for now)
            let userDefaults = UserDefaults.standard
            let keys = ["user_actions", "ai_monitored_apps", "ai_global_permissions", "ai_permission_stats"]
            
            for key in keys {
                userDefaults.removeObject(forKey: key)
            }
            
            // Reset stats
            await MainActor.run {
                stats = PermissionStats()
                saveStats()
            }
            
            logger.info("Cleared all AI data")
        }
    }
    
    func updateStats(screenCaptures: Int = 0, storageUsed: String? = nil, actionsCreated: Int = 0) {
        if screenCaptures > 0 {
            stats.screenCaptures += screenCaptures
        }
        
        if let storage = storageUsed {
            stats.storageUsed = storage
        }
        
        if actionsCreated > 0 {
            stats.actionsCreated += actionsCreated
        }
        
        saveStats()
    }
    
    // MARK: - Permission Validation
    
    func canCaptureScreen(for appName: String) -> Bool {
        guard globalScreenPermission else { return false }
        
        if let app = monitoredApps.first(where: { $0.name == appName }) {
            return app.isEnabled && app.permissions.screenCapture
        }
        
        return false
    }
    
    func canCaptureAudio(for appName: String) -> Bool {
        guard globalAudioPermission else { return false }
        
        if let app = monitoredApps.first(where: { $0.name == appName }) {
            return app.isEnabled && app.permissions.audioCapture
        }
        
        return false
    }
    
    func canMonitorKeyboard(for appName: String) -> Bool {
        guard globalKeyboardPermission else { return false }
        
        if let app = monitoredApps.first(where: { $0.name == appName }) {
            return app.isEnabled && app.permissions.keyboardMonitoring
        }
        
        return false
    }
    
    // MARK: - Persistence
    
    private func savePermissions() {
        let permissions = GlobalPermissions(
            screen: globalScreenPermission,
            audio: globalAudioPermission,
            keyboard: globalKeyboardPermission,
            email: globalEmailPermission,
            calendar: globalCalendarPermission,
            dataRetentionDays: dataRetentionDays,
            autoDeleteSensitive: autoDeleteSensitive
        )
        
        if let data = try? JSONEncoder().encode(permissions) {
            userDefaults.set(data, forKey: "ai_global_permissions")
        }
    }
    
    private func loadPermissions() {
        guard let data = userDefaults.data(forKey: "ai_global_permissions"),
              let permissions = try? JSONDecoder().decode(GlobalPermissions.self, from: data) else {
            return
        }
        
        globalScreenPermission = permissions.screen
        globalAudioPermission = permissions.audio
        globalKeyboardPermission = permissions.keyboard
        globalEmailPermission = permissions.email
        globalCalendarPermission = permissions.calendar
        dataRetentionDays = permissions.dataRetentionDays
        autoDeleteSensitive = permissions.autoDeleteSensitive
    }
    
    private func saveMonitoredApps() {
        // Convert to serializable format (without NSImage)
        let serializable = monitoredApps.map { app in
            SerializableMonitoredApp(
                id: app.id,
                name: app.name,
                bundleID: app.bundleID,
                bundlePath: app.bundlePath,
                isEnabled: app.isEnabled,
                permissions: app.permissions,
                addedDate: app.addedDate
            )
        }
        
        if let data = try? JSONEncoder().encode(serializable) {
            userDefaults.set(data, forKey: "ai_monitored_apps")
        }
    }
    
    private func loadMonitoredApps() {
        guard let data = userDefaults.data(forKey: "ai_monitored_apps"),
              let serializable = try? JSONDecoder().decode([SerializableMonitoredApp].self, from: data) else {
            // Set default apps if none exist
            setDefaultMonitoredApps()
            return
        }
        
        // Convert back to full format (with NSImage)
        monitoredApps = serializable.map { app in
            let icon = app.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            
            return MonitoredApp(
                id: app.id,
                name: app.name,
                bundleID: app.bundleID,
                bundlePath: app.bundlePath,
                icon: icon,
                isEnabled: app.isEnabled,
                permissions: app.permissions,
                addedDate: app.addedDate
            )
        }
    }
    
    private func setDefaultMonitoredApps() {
        let defaultApps = [
            "Slack", "Microsoft Teams", "Discord", "Mail", "Messages",
            "Safari", "Google Chrome", "Zoom", "Microsoft Outlook"
        ]
        
        for appName in defaultApps {
            // Try to find the app in Applications folder
            let appPath = "/Applications/\(appName).app"
            if FileManager.default.fileExists(atPath: appPath) {
                addMonitoredApp(appName, bundleURL: URL(fileURLWithPath: appPath))
            }
        }
    }
    
    private func saveStats() {
        if let data = try? JSONEncoder().encode(stats) {
            userDefaults.set(data, forKey: "ai_permission_stats")
        }
    }
    
    private func loadStats() {
        guard let data = userDefaults.data(forKey: "ai_permission_stats"),
              let loadedStats = try? JSONDecoder().decode(PermissionStats.self, from: data) else {
            return
        }
        
        stats = loadedStats
    }
}

// MARK: - Supporting Types

struct MonitoredApp: Identifiable, Equatable {
    let id: UUID
    let name: String
    let bundleID: String?
    let bundlePath: String?
    let icon: NSImage?
    var isEnabled: Bool
    var permissions: AppPermissions
    let addedDate: Date
    
    static func == (lhs: MonitoredApp, rhs: MonitoredApp) -> Bool {
        return lhs.id == rhs.id
    }
}

struct SerializableMonitoredApp: Codable {
    let id: UUID
    let name: String
    let bundleID: String?
    let bundlePath: String?
    var isEnabled: Bool
    var permissions: AppPermissions
    let addedDate: Date
}

struct AppPermissions: Codable {
    var screenCapture: Bool
    var audioCapture: Bool
    var keyboardMonitoring: Bool
    
    init(screenCapture: Bool = false, audioCapture: Bool = false, keyboardMonitoring: Bool = false) {
        self.screenCapture = screenCapture
        self.audioCapture = audioCapture
        self.keyboardMonitoring = keyboardMonitoring
    }
}

struct GlobalPermissions: Codable {
    let screen: Bool
    let audio: Bool
    let keyboard: Bool
    let email: Bool
    let calendar: Bool
    let dataRetentionDays: Int
    let autoDeleteSensitive: Bool
}

struct PermissionStats: Codable {
    var screenCaptures: Int = 0
    var storageUsed: String = "0 MB"
    var actionsCreated: Int = 0
}

// MARK: - AppStore Integration Extension

extension AppStore {
    /// Check if AI can access specific app
    func canAIAccess(_ appName: String, type: AIAccessType) -> Bool {
        let permissionsManager = AIPermissionsManager.shared
        
        switch type {
        case .screen:
            return permissionsManager.canCaptureScreen(for: appName)
        case .audio:
            return permissionsManager.canCaptureAudio(for: appName)
        case .keyboard:
            return permissionsManager.canMonitorKeyboard(for: appName)
        }
    }
}

enum AIAccessType {
    case screen
    case audio
    case keyboard
}