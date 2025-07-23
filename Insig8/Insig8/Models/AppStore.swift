import SwiftUI
import Combine

// Widget types matching the React Native app
enum WidgetType: String, CaseIterable, Codable {
    case search = "search"
    case calendar = "calendar"
    case clipboard = "clipboard"
    case translation = "translation"
    case emoji = "emoji"
    case calculator = "calculator"
    case settings = "settings"
    case systemActions = "systemActions"
    case windowManager = "windowManager"
    case processManager = "processManager"
    case networkInfo = "networkInfo"
    case shortcuts = "shortcuts"
}

// Main app state management - replacing MobX UIStore
@MainActor
class AppStore: ObservableObject {
    // Published properties for UI updates
    @Published var searchQuery: String = ""
    @Published var selectedWidget: WidgetType = .search
    @Published var isLoading: Bool = false
    @Published var searchResults: [SearchResult] = []
    @Published var selectedIndex: Int = 0
    
    // App preferences
    @Published var theme: ThemeMode = .system
    @Published var showInDock: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var globalHotkey: KeyCombo = KeyCombo(key: .period, modifiers: .command)
    @Published var clipboardLimit: Int = 100
    @Published var searchDepth: Int = 3
    @Published var enableIndexing: Bool = true
    @Published var enableCalculator: Bool = true
    @Published var enableWebSearch: Bool = true
    
    // Services
    let searchService = SearchService()
    // TODO: Add other services in subsequent phases
    // let calendarStore = CalendarStore()
    // let clipboardStore = ClipboardStore()
    // let translationStore = TranslationStore()
    // let emojiStore = EmojiStore()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        loadPreferences()
    }
    
    private func setupBindings() {
        // React to search query changes
        $searchQuery
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.performSearch(query)
            }
            .store(in: &cancellables)
    }
    
    private func loadPreferences() {
        theme = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "system") ?? .system
        showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        clipboardLimit = UserDefaults.standard.integer(forKey: "clipboardLimit").nonZeroOrDefault(100)
        searchDepth = UserDefaults.standard.integer(forKey: "searchDepth").nonZeroOrDefault(3)
        enableIndexing = UserDefaults.standard.bool(forKey: "enableIndexing")
        enableCalculator = UserDefaults.standard.bool(forKey: "enableCalculator")
        enableWebSearch = UserDefaults.standard.bool(forKey: "enableWebSearch")
    }
    
    func performSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            selectedIndex = 0
            return
        }
        
        isLoading = true
        
        Task {
            let results = await searchService.performSearch(query: query)
            await MainActor.run {
                self.searchResults = results
                self.selectedIndex = 0
                self.isLoading = false
            }
        }
    }
    
    func executeCommand() {
        guard selectedIndex < searchResults.count else { return }
        let result = searchResults[selectedIndex]
        
        // Handle widget switching actions specially
        if case .switchToWidget(let widget) = result.action {
            switchToWidget(widget)
            return
        }
        
        // Execute other actions
        searchService.executeAction(result.action)
        
        // Clear search after execution (except for widget switches)
        searchQuery = ""
        searchResults = []
        selectedIndex = 0
    }
    
    func selectPreviousResult() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
    
    func selectNextResult() {
        if selectedIndex < searchResults.count - 1 {
            selectedIndex += 1
        }
    }
    
    func switchToWidget(_ widget: WidgetType) {
        selectedWidget = widget
        searchQuery = ""
        searchResults = []
        selectedIndex = 0
    }
}

// Theme options
enum ThemeMode: String {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

// SearchResult model is defined in Models/SearchResult.swift

// Key combination for global hotkeys
struct KeyCombo: Codable {
    let key: KeyCode
    let modifiers: KeyModifiers
    
    enum KeyCode: String, Codable {
        case space = "Space"
        case enter = "Return"
        case period = "Period"
        // Add more as needed
    }
    
    struct KeyModifiers: OptionSet, Codable {
        let rawValue: Int
        
        static let command = KeyModifiers(rawValue: 1 << 0)
        static let option = KeyModifiers(rawValue: 1 << 1)
        static let control = KeyModifiers(rawValue: 1 << 2)
        static let shift = KeyModifiers(rawValue: 1 << 3)
    }
}

// Extension for safe UserDefaults integer handling
extension Int {
    func nonZeroOrDefault(_ defaultValue: Int) -> Int {
        return self == 0 ? defaultValue : self
    }
}