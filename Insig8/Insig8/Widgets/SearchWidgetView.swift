import SwiftUI

struct SearchWidgetView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        if appStore.searchResults.isEmpty && !appStore.searchQuery.isEmpty && !appStore.isLoading {
            EmptySearchView()
        } else if appStore.isLoading {
            LoadingView()
        } else {
            SearchResultsListView()
        }
    }
}

struct SearchResultsListView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        ScrollViewReader { proxy in
            List(appStore.searchResults.indices, id: \.self) { index in
                SearchResultRow(
                    result: appStore.searchResults[index],
                    isSelected: index == appStore.selectedIndex
                )
                .id(index)
                .listRowSeparator(.hidden)
                .listRowBackground(
                    index == appStore.selectedIndex ?
                    Color.accentColor.opacity(0.2) : Color.clear
                )
                .onTapGesture {
                    appStore.selectedIndex = index
                    appStore.executeCommand()
                }
            }
            .listStyle(.plain)
            .onChange(of: appStore.selectedIndex) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .onKeyPress(.upArrow) {
            appStore.selectPreviousResult()
            return .handled
        }
        .onKeyPress(.downArrow) {
            appStore.selectNextResult()
            return .handled
        }
        .onKeyPress(.return) {
            appStore.executeCommand()
            return .handled
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: result.icon)
                .font(.title2)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 30)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body)
                    .fontWeight(isSelected ? .medium : .regular)
                
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Type indicator
            if isSelected {
                Text(resultTypeLabel)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
    
    private var resultTypeLabel: String {
        switch result.type {
        case .application: return "App"
        case .file: return "File"
        case .systemAction: return "Action"
        case .calendarEvent: return "Event"
        case .clipboardItem: return "Clipboard"
        case .emoji: return "Emoji"
        case .action: return "AI Action"
        case .suggestion: return "AI Suggestion"
        case .custom: return "Custom"
        }
    }
}

struct EmptySearchView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No results for \"\(appStore.searchQuery)\"")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Try searching for apps, files, or system actions")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            
            Text("Searching...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SearchWidgetView()
        .environmentObject(AppStore.shared)
        .frame(width: 800, height: 600)
}