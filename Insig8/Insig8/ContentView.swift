import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appStore: AppStore
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search/Command input
            SearchInputView(isSearchFieldFocused: $isSearchFieldFocused)
                .padding()
            
            Divider()
            
            // Dynamic content based on selected widget
            WidgetContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Focus is now handled by notification from PanelManager
        }
        .background(KeyEventHandlingView(appStore: appStore))
    }
}

struct SearchInputView: View {
    @EnvironmentObject var appStore: AppStore
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    var body: some View {
        EnhancedSearchInput(
            text: $appStore.searchQuery,
            placeholder: placeholderText,
            leadingIcon: currentIcon,
            suggestions: searchSuggestions,
            onSuggestionTap: { suggestion in
                // Handle suggestion selection
                appStore.searchQuery = suggestion
            },
            onSubmit: {
                appStore.executeCommand()
            }
        )
    }
    
    private var currentIcon: String {
        switch appStore.selectedWidget {
        case .search: return "magnifyingglass"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .translation: return "globe"
        case .emoji: return "face.smiling"
        case .settings: return "gear"
        default: return "command"
        }
    }
    
    private var placeholderText: String {
        switch appStore.selectedWidget {
        case .search: return "Search apps, files, and more..."
        case .calendar: return "Search calendar events..."
        case .clipboard: return "Search clipboard history..."
        case .translation: return "Enter text to translate..."
        case .emoji: return "Search emojis..."
        case .settings: return "Search settings..."
        default: return "Type a command..."
        }
    }
    
    private var searchSuggestions: [String] {
        switch appStore.selectedWidget {
        case .search:
            return ["Applications", "System Preferences", "Documents", "Downloads", "Desktop"]
        case .translation:
            return ["Hello", "Thank you", "Good morning", "How are you?", "Goodbye"]
        case .emoji:
            return ["happy", "sad", "love", "party", "thumbs up", "heart", "smile"]
        default:
            return []
        }
    }
}

struct WidgetContentView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        Group {
            switch appStore.selectedWidget {
            case .search:
                SearchWidgetView()
            case .calendar:
                CalendarWidgetView()
            case .clipboard:
                ClipboardWidgetView()
            case .translation:
                TranslationWidgetView()
            case .emoji:
                EmojiWidgetView()
            case .settings:
                SettingsWidgetView()
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Key Event Handling
struct KeyEventHandlingView: NSViewRepresentable {
    let appStore: AppStore
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerView()
        view.appStore = appStore
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyHandlerView: NSView {
    var appStore: AppStore?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard let appStore = appStore else { return }
        
        // Handle special key combinations first
        let modifiers = event.modifierFlags
        
        // Command + Escape: Always return to search widget
        if event.keyCode == 53 && modifiers.contains(.command) {
            appStore.switchToWidget(.search)
            return
        }
        
        // Escape key: Progressive back navigation
        if event.keyCode == 53 {
            if appStore.selectedWidget != .search {
                // If in another widget, go back to search
                appStore.switchToWidget(.search)
            } else if !appStore.searchQuery.isEmpty {
                // If in search with query, clear query
                appStore.searchQuery = ""
            } else {
                // If in search with empty query, close panel
                PanelManager.shared.hideWindow()
            }
            return
        }
        
        // Arrow key navigation and Enter (prioritize over text field when results exist)
        if appStore.selectedWidget == .search && !appStore.searchResults.isEmpty {
            switch event.keyCode {
            case 126: // Up arrow
                appStore.selectPreviousResult()
                return
            case 125: // Down arrow
                appStore.selectNextResult()
                return
            case 36: // Enter key
                appStore.executeCommand()
                return
            default:
                break
            }
        }
        
        // Command + W: Close window (Raycast pattern)
        if event.keyCode == 13 && modifiers.contains(.command) { // W key
            PanelManager.shared.hideWindow()
            return
        }
        
        // Command + Comma: Open settings (Raycast pattern)
        if event.keyCode == 43 && modifiers.contains(.command) { // Comma key
            appStore.switchToWidget(.settings)
            return
        }
        
        super.keyDown(with: event)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
        .frame(width: 800, height: 600)
}