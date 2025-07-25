import Foundation

// MARK: - Search Result Model
struct SearchResult: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let type: ResultType
    let action: Action
    let relevanceScore: Double
    
    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        type: ResultType,
        action: Action,
        relevanceScore: Double = 0.0
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.type = type
        self.action = action
        self.relevanceScore = relevanceScore
    }
    
    // MARK: - Result Types
    enum ResultType: Codable, Equatable {
        case application
        case file
        case systemAction
        case calendarEvent
        case clipboardItem
        case emoji
        case action
        case suggestion
        case custom(String)
        
        var displayName: String {
            switch self {
            case .application: return "App"
            case .file: return "File"
            case .systemAction: return "Action"
            case .calendarEvent: return "Event"
            case .clipboardItem: return "Clipboard"
            case .emoji: return "Emoji"
            case .action: return "Action"
            case .suggestion: return "Suggestion"
            case .custom(let type): return type.capitalized
            }
        }
    }
    
    // MARK: - Actions
    enum Action: Codable, Equatable {
        case openApplication(path: String)
        case openFile(url: String) // Using String for Codable compliance
        case openURL(url: String)
        case copyToClipboard(text: String)
        case openSystemPreferences
        case openActivityMonitor
        case openTerminal
        case openFinder
        case emptyTrash
        case systemSleep
        case lockScreen
        case logOut
        case restart
        case shutdown
        case switchToWidget(WidgetType)
        case performSearch(String)
        case custom(String)
        // Meeting Actions
        case startMeeting
        case stopMeeting
        case generateMeetingSummary
        case enrollSpeaker
        
        var description: String {
            switch self {
            case .openApplication: return "Open Application"
            case .openFile: return "Open File"
            case .openURL: return "Open URL"
            case .copyToClipboard: return "Copy to Clipboard"
            case .openSystemPreferences: return "Open System Preferences"
            case .openActivityMonitor: return "Open Activity Monitor"
            case .openTerminal: return "Open Terminal"
            case .openFinder: return "Open Finder"
            case .emptyTrash: return "Empty Trash"
            case .systemSleep: return "Sleep"
            case .lockScreen: return "Lock Screen"
            case .logOut: return "Log Out"
            case .restart: return "Restart"
            case .shutdown: return "Shut Down"
            case .switchToWidget: return "Switch to Widget"
            case .performSearch: return "Perform Search"
            case .custom(let action): return action
            // Meeting Actions
            case .startMeeting: return "Start Meeting"
            case .stopMeeting: return "Stop Meeting"
            case .generateMeetingSummary: return "Generate Summary"
            case .enrollSpeaker: return "Enroll Speaker"
            }
        }
    }
}

// MARK: - Sample Data for Development
extension SearchResult {
    static let samples: [SearchResult] = [
        SearchResult(
            id: "1",
            title: "Safari",
            subtitle: "Web Browser",
            icon: "safari",
            type: .application,
            action: .openApplication(path: "/Applications/Safari.app"),
            relevanceScore: 0.9
        ),
        SearchResult(
            id: "2",
            title: "Documents",
            subtitle: "/Users/user/Documents",
            icon: "folder",
            type: .file,
            action: .openFile(url: "/Users/user/Documents"),
            relevanceScore: 0.8
        ),
        SearchResult(
            id: "3",
            title: "System Preferences",
            subtitle: "Configure system settings",
            icon: "gear",
            type: .systemAction,
            action: .openSystemPreferences,
            relevanceScore: 0.7
        ),
        SearchResult(
            id: "4",
            title: "2 + 3 = 5",
            subtitle: "Calculator result",
            icon: "function",
            type: .custom("calculator"),
            action: .copyToClipboard(text: "5"),
            relevanceScore: 1.0
        ),
        SearchResult(
            id: "5",
            title: "Search Google for \"swift\"",
            subtitle: "Web search",
            icon: "globe",
            type: .custom("web"),
            action: .openURL(url: "https://www.google.com/search?q=swift"),
            relevanceScore: 0.3
        )
    ]
}