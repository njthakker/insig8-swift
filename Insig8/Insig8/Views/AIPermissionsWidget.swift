//
//  AIPermissionsWidget.swift
//  Insig8
//
//  AI settings widget for managing app-specific permissions
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AIPermissionsWidget: View {
    @EnvironmentObject var appStore: AppStore
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("AI Permissions")
                        .font(.headline)
                    Text("Control what data AI can access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // AI Status Indicator
                AIStatusIndicator()
            }
            
            Divider()
            
            // Global Permissions
            GlobalPermissionsSection()
            
            Divider()
            
            // App-Specific Permissions
            AppSpecificPermissionsSection()
            
            Divider()
            
            // Data Controls
            DataControlsSection()
        }
        .padding()
    }
}

struct GlobalPermissionsSection: View {
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Permissions")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                PermissionToggle(
                    title: "Screen Monitoring",
                    description: "Capture and analyze screen content",
                    icon: "camera.viewfinder",
                    isEnabled: $permissionsManager.globalScreenPermission,
                    systemPermissionRequired: true
                ) {
                    permissionsManager.requestScreenRecordingPermission()
                }
                
                PermissionToggle(
                    title: "Audio Capture",
                    description: "Record meetings and calls for transcription",
                    icon: "mic",
                    isEnabled: $permissionsManager.globalAudioPermission,
                    systemPermissionRequired: true
                ) {
                    permissionsManager.requestMicrophonePermission()
                }
                
                PermissionToggle(
                    title: "Keyboard Monitoring",
                    description: "Track typing context for better AI understanding",
                    icon: "keyboard",
                    isEnabled: $permissionsManager.globalKeyboardPermission,
                    systemPermissionRequired: true
                ) {
                    permissionsManager.requestAccessibilityPermission()
                }
                
                PermissionToggle(
                    title: "Email Integration",
                    description: "Monitor and analyze email conversations",
                    icon: "envelope",
                    isEnabled: $permissionsManager.globalEmailPermission,
                    systemPermissionRequired: false
                )
                
                PermissionToggle(
                    title: "Calendar Integration",
                    description: "Access calendar events and meeting schedules",
                    icon: "calendar",
                    isEnabled: $permissionsManager.globalCalendarPermission,
                    systemPermissionRequired: false
                )
            }
        }
    }
}

struct AppSpecificPermissionsSection: View {
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    @State private var selectedApp: MonitoredApp?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App-Specific Permissions")
                    .font(.headline)
                
                Spacer()
                
                Button("Add App") {
                    showAppPicker()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(permissionsManager.monitoredApps) { app in
                        AppPermissionCard(app: app)
                            .onTapGesture {
                                selectedApp = app
                            }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            if permissionsManager.monitoredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No apps configured")
                        .foregroundColor(.secondary)
                    
                    Text("Add apps to enable AI monitoring")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .sheet(item: $selectedApp) { app in
            AppDetailPermissionsView(app: app)
        }
    }
    
    private func showAppPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let appName = url.deletingPathExtension().lastPathComponent
                Task { @MainActor in
                    permissionsManager.addMonitoredApp(appName, bundleURL: url)
                }
            }
        }
    }
}

struct AppPermissionCard: View {
    let app: MonitoredApp
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(app.isEnabled ? .green : .gray)
                    .frame(width: 8, height: 8)
            }
            
            // Permission summary
            VStack(alignment: .leading, spacing: 2) {
                PermissionStatusRow(
                    icon: "camera.viewfinder",
                    enabled: app.permissions.screenCapture
                )
                
                PermissionStatusRow(
                    icon: "mic",
                    enabled: app.permissions.audioCapture
                )
                
                PermissionStatusRow(
                    icon: "keyboard",
                    enabled: app.permissions.keyboardMonitoring
                )
            }
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 180)
    }
}

struct PermissionStatusRow: View {
    let icon: String
    let enabled: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(enabled ? .green : .secondary)
            
            Text(enabled ? "Enabled" : "Disabled")
                .foregroundColor(enabled ? .primary : .secondary)
            
            Spacer()
        }
    }
}

struct PermissionToggle: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isEnabled: Bool
    let systemPermissionRequired: Bool
    var onPermissionRequest: (() -> Void)? = nil
    
    @State private var showingPermissionAlert = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isEnabled ? .blue : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: isEnabled) { _, newValue in
                    if newValue && systemPermissionRequired {
                        // Check if system permission is granted
                        checkSystemPermission()
                    }
                }
        }
        .padding(.vertical, 4)
        .alert("System Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open System Settings") {
                if let onRequest = onPermissionRequest {
                    onRequest()
                } else {
                    openSystemSettings()
                }
            }
            Button("Cancel") {
                isEnabled = false
            }
        } message: {
            Text("This feature requires system permission. Please enable it in System Settings > Privacy & Security.")
        }
    }
    
    private func checkSystemPermission() {
        // Simplified check - in production, would check actual system permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingPermissionAlert = true
        }
    }
    
    private func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }
}

struct DataControlsSection: View {
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Controls")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Data Retention")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("How long to keep captured data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $permissionsManager.dataRetentionDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Auto-delete Sensitive Data")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Automatically remove passwords, cards, etc.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $permissionsManager.autoDeleteSensitive)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                
                Divider()
                
                // Data Usage Statistics
                DataUsageStatsView()
                
                Divider()
                
                // Clear Data Button
                Button("Clear All AI Data") {
                    permissionsManager.clearAllData()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
    }
}

struct DataUsageStatsView: View {
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Usage")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                StatItem(
                    label: "Screen Captures",
                    value: "\(permissionsManager.stats.screenCaptures)",
                    icon: "camera.viewfinder"
                )
                
                Spacer()
                
                StatItem(
                    label: "Storage Used",
                    value: permissionsManager.stats.storageUsed,
                    icon: "internaldrive"
                )
                
                Spacer()
                
                StatItem(
                    label: "Actions Created",
                    value: "\(permissionsManager.stats.actionsCreated)",
                    icon: "checklist"
                )
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.caption)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 80)
    }
}

struct AIStatusIndicator: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appStore.aiService.isAIAvailable ? .green : .red)
                .frame(width: 8, height: 8)
            
            Text(appStore.aiService.isAIAvailable ? "AI Online" : "AI Offline")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct AppDetailPermissionsView: View {
    let app: MonitoredApp
    @StateObject private var permissionsManager = AIPermissionsManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // App header
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(app.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(app.bundleID ?? "Unknown Bundle ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("Enabled", isOn: .constant(app.isEnabled))
                        .toggleStyle(.switch)
                }
                
                Divider()
                
                // Detailed permissions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Permissions")
                        .font(.headline)
                    
                    DetailedPermissionRow(
                        title: "Screen Capture",
                        description: "Monitor this app's windows and content",
                        icon: "camera.viewfinder",
                        isEnabled: .constant(app.permissions.screenCapture)
                    )
                    
                    DetailedPermissionRow(
                        title: "Audio Capture",
                        description: "Record audio when this app is active",
                        icon: "mic",
                        isEnabled: .constant(app.permissions.audioCapture)
                    )
                    
                    DetailedPermissionRow(
                        title: "Keyboard Monitoring",
                        description: "Track typing in this app",
                        icon: "keyboard",
                        isEnabled: .constant(app.permissions.keyboardMonitoring)
                    )
                }
                
                Spacer()
                
                // Remove app button
                Button("Remove App") {
                    permissionsManager.removeMonitoredApp(app.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("App Permissions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct DetailedPermissionRow: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isEnabled ? .blue : .secondary)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AIPermissionsWidget()
        .environmentObject(AppStore.shared)
        .frame(width: 600, height: 700)
}