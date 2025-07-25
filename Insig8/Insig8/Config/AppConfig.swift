import Foundation

/// App configuration for meeting-focused mode
struct AppConfig {
    /// When true, disables non-meeting functionality and reduces logging
    static let meetingOnlyMode = true
    
    /// Enable verbose logging for debugging
    static let verboseLogging = false
    
    /// Meeting-focused feature flags
    static let enableAIMonitoring = !meetingOnlyMode
    static let enableScreenCapture = !meetingOnlyMode
    static let enableClipboardMonitoring = !meetingOnlyMode
    static let enableAppFocusMonitoring = !meetingOnlyMode
    
    /// Log helper for meeting-focused mode
    static func log(_ message: String, level: LogLevel = .info) {
        #if DEBUG
        guard verboseLogging || level == .error || (!meetingOnlyMode && level == .info) else { return }
        
        let prefix = switch level {
        case .error: "❌"
        case .warning: "⚠️"
        case .info: "ℹ️"
        case .debug: "🔍"
        }
        
        print("\(prefix) \(message)")
        #endif
    }
}

enum LogLevel {
    case error, warning, info, debug
}