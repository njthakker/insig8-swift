import Foundation
import AppKit
import Combine

// MARK: - Search Service
@MainActor
class SearchService: ObservableObject {
    @Published var isSearching = false
    
    private let fileManager = FileManager.default
    private let workspace = NSWorkspace.shared
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Main Search Function
    func performSearch(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        isSearching = true
        defer { isSearching = false }
        
        // Results will be collected from concurrent tasks
        
        // Cancel previous search
        searchTask?.cancel()
        
        return await withTaskGroup(of: [SearchResult].self) { group in
            // Application search
            group.addTask { [weak self] in
                await self?.searchApplications(query: query) ?? []
            }
            
            // File search
            group.addTask { [weak self] in
                await self?.searchFiles(query: query) ?? []
            }
            
            // System actions
            group.addTask { [weak self] in
                await self?.searchSystemActions(query: query) ?? []
            }
            
            // Calculator
            group.addTask { [weak self] in
                await self?.evaluateCalculation(query: query) ?? []
            }
            
            // Widget navigation
            group.addTask { [weak self] in
                await self?.searchWidgets(query: query) ?? []
            }
            
            // Web search suggestions
            group.addTask { [weak self] in
                await self?.generateWebSearchSuggestions(query: query) ?? []
            }
            
            var allResults: [SearchResult] = []
            for await searchResults in group {
                allResults.append(contentsOf: searchResults)
            }
            
            // Sort by relevance and type priority
            return allResults.sorted { lhs, rhs in
                // Prioritize exact matches
                if lhs.title.lowercased() == query.lowercased() {
                    return true
                }
                if rhs.title.lowercased() == query.lowercased() {
                    return false
                }
                
                // Then by type priority
                let lhsPriority = lhs.type.priority
                let rhsPriority = rhs.type.priority
                
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                
                // Finally by relevance score
                return lhs.relevanceScore > rhs.relevanceScore
            }
        }
    }
    
    // MARK: - Application Search
    private func searchApplications(query: String) async -> [SearchResult] {
        var results: [SearchResult] = []
        let lowercaseQuery = query.lowercased()
        
        // Use NSWorkspace to find applications (sandbox-friendly approach)
        let workspace = NSWorkspace.shared
        
        // Search running applications first
        for app in workspace.runningApplications {
            if let localizedName = app.localizedName,
               localizedName.lowercased().contains(lowercaseQuery) {
                
                let relevanceScore = calculateRelevanceScore(text: localizedName, query: query)
                
                results.append(SearchResult(
                    id: app.bundleIdentifier ?? UUID().uuidString,
                    title: localizedName,
                    subtitle: "Application • Running",
                    icon: "app",
                    type: .application,
                    action: .openApplication(path: app.bundleURL?.path ?? ""),
                    relevanceScore: relevanceScore + 0.1 // Boost running apps
                ))
            }
        }
        
        // Try to find more applications using a known list of common apps
        let commonApps = [
            ("Safari", "com.apple.Safari"),
            ("Finder", "com.apple.finder"),
            ("Mail", "com.apple.mail"),
            ("Calendar", "com.apple.iCal"),
            ("Notes", "com.apple.Notes"),
            ("Reminders", "com.apple.reminders"),
            ("Photos", "com.apple.Photos"),
            ("Music", "com.apple.Music"),
            ("Calculator", "com.apple.calculator"),
            ("Terminal", "com.apple.Terminal"),
            ("System Preferences", "com.apple.systempreferences"),
            ("App Store", "com.apple.appstore"),
            ("Xcode", "com.apple.dt.Xcode"),
            ("TextEdit", "com.apple.TextEdit"),
            ("Preview", "com.apple.Preview")
        ]
        
        for (appName, bundleId) in commonApps {
            if appName.lowercased().contains(lowercaseQuery),
               let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                
                // Check if not already added
                if !results.contains(where: { $0.title == appName }) {
                    let relevanceScore = calculateRelevanceScore(text: appName, query: query)
                    
                    results.append(SearchResult(
                        id: bundleId,
                        title: appName,
                        subtitle: "Application",
                        icon: "app",
                        type: .application,
                        action: .openApplication(path: appURL.path),
                        relevanceScore: relevanceScore
                    ))
                }
            }
        }
        
        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    // MARK: - File Search
    private func searchFiles(query: String) async -> [SearchResult] {
        let searchDirectories = [
            NSHomeDirectory(),
            "\(NSHomeDirectory())/Documents",
            "\(NSHomeDirectory())/Desktop",
            "\(NSHomeDirectory())/Downloads"
        ]
        
        var results: [SearchResult] = []
        let lowercaseQuery = query.lowercased()
        
        for directory in searchDirectories {
            let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            
            guard let enumerator = enumerator else { continue }
            
            // Convert enumerator to array for Swift 6 compatibility
            let urls = enumerator.allObjects.compactMap { $0 as? URL }
            
            for url in urls {
                // Limit search depth to avoid performance issues
                let depth = url.pathComponents.count - URL(fileURLWithPath: directory).pathComponents.count
                if depth > 3 { continue }
                
                let fileName = url.lastPathComponent
                
                if fileName.lowercased().contains(lowercaseQuery) {
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let relevanceScore = calculateRelevanceScore(text: fileName, query: query)
                    
                    results.append(SearchResult(
                        id: url.path,
                        title: fileName,
                        subtitle: url.path,
                        icon: isDirectory ? "folder" : "doc",
                        type: .file,
                        action: .openFile(url: url.path),
                        relevanceScore: relevanceScore
                    ))
                }
                
                // Limit results to prevent UI slowdown
                if results.count >= 20 {
                    break
                }
            }
        }
        
        return results
    }
    
    // MARK: - System Actions
    private func searchSystemActions(query: String) async -> [SearchResult] {
        let systemActions: [(String, String, String, SearchResult.Action)] = [
            ("System Preferences", "Open System Preferences", "gear", .openSystemPreferences),
            ("Activity Monitor", "Monitor system activity", "speedometer", .openActivityMonitor),
            ("Terminal", "Open Terminal", "terminal", .openTerminal),
            ("Finder", "Open Finder", "folder", .openFinder),
            ("Trash", "Empty Trash", "trash", .emptyTrash),
            ("Sleep", "Put system to sleep", "moon", .systemSleep),
            ("Lock Screen", "Lock the screen", "lock", .lockScreen),
            ("Log Out", "Log out current user", "person.crop.circle.badge.xmark", .logOut),
            ("Restart", "Restart the system", "arrow.clockwise", .restart),
            ("Shut Down", "Shut down the system", "power", .shutdown),
            // Meeting Actions
            ("Start Meeting", "Start recording a new meeting", "record.circle", .startMeeting),
            ("Stop Meeting", "Stop current meeting recording", "stop.circle", .stopMeeting),
            ("Meeting Summary", "Generate summary of current meeting", "doc.text", .generateMeetingSummary),
            ("Enroll Speaker", "Add a new speaker profile", "person.crop.circle.badge.plus", .enrollSpeaker)
        ]
        
        let lowercaseQuery = query.lowercased()
        
        return systemActions.compactMap { (title, subtitle, icon, action) in
            if title.lowercased().contains(lowercaseQuery) {
                let relevanceScore = calculateRelevanceScore(text: title, query: query)
                return SearchResult(
                    id: title,
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    type: .systemAction,
                    action: action,
                    relevanceScore: relevanceScore
                )
            }
            return nil
        }
    }
    
    // MARK: - Calculator
    private func evaluateCalculation(query: String) async -> [SearchResult] {
        let expression = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate basic math expressions more strictly
        let mathPattern = #"^[\d\+\-\*/\.\(\)\s]+$"#
        
        guard expression.range(of: mathPattern, options: .regularExpression) != nil,
              !expression.isEmpty,
              expression.count > 1, // Must have at least 2 characters
              expression.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil else { // Must contain at least one digit
            return []
        }
        
        // Check for invalid patterns
        let invalidPatterns = [
            #"\+\s*$"#,  // Ends with +
            #"-\s*$"#,   // Ends with -
            #"\*\s*$"#,  // Ends with *
            #"/\s*$"#,   // Ends with /
            #"\.\s*$"#,  // Ends with .
            #"^\s*[\+\*/]"#, // Starts with operator (except -)
            #"[\+\-\*/]{2,}"#, // Multiple consecutive operators
            #"==+"# // Contains ==
        ]
        
        for pattern in invalidPatterns {
            if expression.range(of: pattern, options: .regularExpression) != nil {
                return []
            }
        }
        
        // Use NSExpression for safe calculation
        let mathExpression = NSExpression(format: expression)
        
        // NSExpression evaluation can return nil for invalid expressions
        if let result = mathExpression.expressionValue(with: nil, context: nil) as? NSNumber {
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 10
            formatter.minimumFractionDigits = 0
            let formattedResult = formatter.string(from: result) ?? "\(result)"
            
            return [SearchResult(
                id: "calc_\(expression)",
                title: "\(expression) = \(formattedResult)",
                subtitle: "Calculator result • Press Enter to copy",
                icon: "function",
                type: .custom("calculator"),
                action: .copyToClipboard(text: formattedResult),
                relevanceScore: 1.0
            )]
        }
        
        return []
    }
    
    // MARK: - Widget Navigation
    private func searchWidgets(query: String) async -> [SearchResult] {
        let baseWidgets = [
            ("Calendar", "calendar", "View calendar events and schedule", "calendar"),
            ("Clipboard Manager", "clipboard", "View and manage clipboard history", "doc.on.clipboard"),
            ("Settings", "settings", "App preferences and configuration", "gear"),
            ("Translation", "translation", "Translate text between languages", "globe"),
            ("Emoji Picker", "emoji", "Browse and search emojis", "face.smiling"),
            ("Process Manager", "processes", "View and manage running processes", "cpu"),
            ("Network Info", "network", "View network information and status", "wifi")
        ]
        
        // Always include meeting widgets - make them persistent
        let meetingWidgets: [(String, String, String, String)] = [
            ("Meeting Transcription", "meeting", "Record and transcribe meetings with AI", "video"),
            ("Meeting Summary", "meeting", "Generate and view meeting summaries", "doc.text"),
            ("Start Meeting", "meeting", "Begin a new meeting recording session", "record.circle"),
            ("Meeting History", "meeting", "View past meeting recordings and summaries", "clock"),
            ("Live Meeting", "meeting", "Current meeting session", "record.circle")
        ]
        
        let allWidgets = baseWidgets + meetingWidgets
        
        let lowercasedQuery = query.lowercased()
        var results: [SearchResult] = []
        
        for (title, key, description, icon) in allWidgets {
            // More flexible matching for meeting widgets
            let matchesQuery = title.lowercased().contains(lowercasedQuery) || 
                              key.lowercased().contains(lowercasedQuery) ||
                              description.lowercased().contains(lowercasedQuery)
            
            let matchesMeetingTerms = lowercasedQuery.contains("summary") ||
                                     lowercasedQuery.contains("transcript") ||
                                     lowercasedQuery.contains("recording") ||
                                     lowercasedQuery.contains("meet") ||
                                     lowercasedQuery.contains("live") ||
                                     lowercasedQuery.contains("history")
            
            // Always show meeting widgets if query is meeting-related or matches title
            if matchesQuery || (key == "meeting" && matchesMeetingTerms) {
                let relevanceScore = calculateRelevanceScore(text: title, query: query)
                
                // Boost meeting-related results more aggressively
                let boost = (key == "meeting") ? 0.5 : 0.2
                
                results.append(SearchResult(
                    id: "widget_\(key)_\(title.replacingOccurrences(of: " ", with: "_"))",
                    title: title,
                    subtitle: description,
                    icon: icon,
                    type: .custom("widget"),
                    action: .switchToWidget(WidgetType(rawValue: key) ?? .search),
                    relevanceScore: relevanceScore + boost
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Web Search Suggestions
    private func generateWebSearchSuggestions(query: String) async -> [SearchResult] {
        guard query.count >= 3 else { return [] }
        
        let searchEngines: [(String, String, String)] = [
            ("Google", "https://www.google.com/search?q=", "globe"),
            ("DuckDuckGo", "https://duckduckgo.com/?q=", "shield"),
            ("Bing", "https://www.bing.com/search?q=", "magnifyingglass")
        ]
        
        return searchEngines.map { (name, baseURL, icon) in
            SearchResult(
                id: "web_\(name)_\(query)",
                title: "Search \(name) for \"\(query)\"",
                subtitle: "Web search",
                icon: icon,
                type: .custom("web"),
                action: .openURL(url: "\(baseURL)\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"),
                relevanceScore: 0.3
            )
        }
    }
    
    // MARK: - Relevance Scoring
    private func calculateRelevanceScore(text: String, query: String) -> Double {
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // Exact match
        if lowercaseText == lowercaseQuery {
            return 1.0
        }
        
        // Starts with query
        if lowercaseText.hasPrefix(lowercaseQuery) {
            return 0.9
        }
        
        // Contains query as whole word
        if lowercaseText.contains(" \(lowercaseQuery) ") || 
           lowercaseText.hasPrefix("\(lowercaseQuery) ") ||
           lowercaseText.hasSuffix(" \(lowercaseQuery)") {
            return 0.8
        }
        
        // Contains query
        if lowercaseText.contains(lowercaseQuery) {
            return 0.7
        }
        
        // Fuzzy matching (simple implementation)
        let commonChars = Set(lowercaseText).intersection(Set(lowercaseQuery))
        let fuzzyScore = Double(commonChars.count) / Double(max(lowercaseText.count, lowercaseQuery.count))
        
        return fuzzyScore * 0.5
    }
    
    // MARK: - Execute Action
    func executeAction(_ action: SearchResult.Action) {
        Task { @MainActor in
            switch action {
            case .openApplication(let path):
                workspace.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
                
            case .openFile(let urlString):
                let url = URL(fileURLWithPath: urlString)
                workspace.open(url)
                
            case .openURL(let urlString):
                if let url = URL(string: urlString) {
                    workspace.open(url)
                }
                
            case .copyToClipboard(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                
            case .openSystemPreferences:
                workspace.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
                
            case .openActivityMonitor:
                workspace.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                
            case .openTerminal:
                workspace.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                
            case .openFinder:
                workspace.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
                
            case .emptyTrash:
                // Use AppleScript to empty trash since NSWorkspace doesn't have direct method
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", "tell application \"Finder\" to empty trash"]
                task.launch()
                
            case .systemSleep:
                let task = Process()
                task.launchPath = "/usr/bin/pmset"
                task.arguments = ["sleepnow"]
                task.launch()
                
            case .lockScreen:
                let task = Process()
                task.launchPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
                task.arguments = ["-suspend"]
                task.launch()
                
            case .logOut:
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", "tell application \"System Events\" to log out"]
                task.launch()
                
            case .restart:
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", "tell application \"System Events\" to restart"]
                task.launch()
                
            case .shutdown:
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", "tell application \"System Events\" to shut down"]
                task.launch()
                
            case .switchToWidget(_):
                // Widget switching is handled in AppStore.executeCommand()
                // This case should not be reached here
                break
                
            case .performSearch(let query):
                // This should trigger a new search with the suggested query
                // Implementation depends on how AppStore handles search delegation
                print("Performing AI suggested search: \(query)")
                
            case .custom(let identifier):
                print("Custom action: \(identifier)")
                
            // Meeting Actions
            case .startMeeting:
                AppStore.shared.switchToWidget(.meeting)
                Task {
                    try? await AppStore.shared.meetingService.startMeeting()
                }
                
            case .stopMeeting:
                Task {
                    try? await AppStore.shared.meetingService.stopMeeting()
                }
                
            case .generateMeetingSummary:
                AppStore.shared.switchToWidget(.meeting)
                // Summary generation is handled in the service
                
            case .enrollSpeaker:
                AppStore.shared.switchToWidget(.meeting)
                // Speaker enrollment is handled in the UI
            }
        }
    }
}

// MARK: - Search Result Type Extension
extension SearchResult.ResultType {
    var priority: Int {
        switch self {
        case .application: return 1
        case .action: return 0  // AI actions get highest priority
        case .file: return 2
        case .systemAction: return 3
        case .suggestion: return 6  // AI suggestions get lower priority
        case .custom("calculator"): return 1
        case .custom("web"): return 5
        default: return 4
        }
    }
}

// MARK: - Action enum is defined in Models/SearchResult.swift