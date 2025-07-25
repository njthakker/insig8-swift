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
            // Set initial focus
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            isSearchFieldFocused = true
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
            isFocused: $isSearchFieldFocused,
            onSuggestionTap: { suggestion in
                // Handle suggestion selection
                appStore.searchQuery = suggestion
            },
            onSubmit: {
                // On Enter, perform full AI search then execute command
                appStore.performFullSearchOnEnter(appStore.searchQuery)
                // Small delay to let the AI search complete before executing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Task {
                        await appStore.executeCommand()
                    }
                }
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
        case .aiMonitor: return "brain.head.profile"
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
        case .aiMonitor: return "Monitor AI processing..."
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
                if appStore.searchQuery.isEmpty {
                    ActionDashboardView()
                } else {
                    SearchWidgetView()
                }
            case .calendar:
                CalendarWidgetView()
            case .clipboard:
                ClipboardWidgetView()
            case .translation:
                TranslationWidgetView()
            case .emoji:
                EmojiWidgetView()
            case .settings:
                // Check if AI settings should be shown
                if appStore.searchQuery.contains("ai") && appStore.searchQuery.contains("permission") {
                    AIPermissionsWidget()
                } else {
                    SettingsWidgetView()
                }
            case .aiMonitor:
                AIMonitorWidget()
            case .meeting:
                MeetingWidgetView()
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
    
    override var acceptsFirstResponder: Bool { false } // Don't accept first responder
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let appStore = appStore else { return false }
        
        // Handle special key combinations first
        let modifiers = event.modifierFlags
        
        // Command + Escape: Always return to search widget
        if event.keyCode == 53 && modifiers.contains(.command) {
            appStore.switchToWidget(.search)
            return true
        }
        
        // Command + W: Close window (Raycast pattern)
        if event.keyCode == 13 && modifiers.contains(.command) { // W key
            PanelManager.shared.hideWindow()
            return true
        }
        
        // Command + Comma: Open settings (Raycast pattern)
        if event.keyCode == 43 && modifiers.contains(.command) { // Comma key
            appStore.switchToWidget(.settings)
            return true
        }
        
        // For non-command keys, check if we should handle them
        if !modifiers.contains(.command) {
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
                return true
            }
            
            // Arrow key navigation and Enter (prioritize over text field when results exist)
            if appStore.selectedWidget == .search && !appStore.searchResults.isEmpty {
                switch event.keyCode {
                case 126: // Up arrow
                    appStore.selectPreviousResult()
                    return true
                case 125: // Down arrow
                    appStore.selectNextResult()
                    return true
                case 36: // Enter key
                    Task {
                        await appStore.executeCommand()
                    }
                    return true
                default:
                    break
                }
            }
        }
        
        return super.performKeyEquivalent(with: event)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore.shared)
        .frame(width: 800, height: 600)
}