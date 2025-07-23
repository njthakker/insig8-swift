import SwiftUI
import Combine
import AppKit

struct ClipboardWidgetView: View {
    @StateObject private var clipboardStore = ClipboardStore()
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        if clipboardStore.history.isEmpty {
            EmptyClipboardView()
        } else {
            ClipboardHistoryList(clipboardStore: clipboardStore)
        }
    }
}

struct EmptyClipboardView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Clipboard is empty")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Copy something to see it here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ClipboardHistoryList: View {
    @ObservedObject var clipboardStore: ClipboardStore
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        List(clipboardStore.filteredHistory(for: appStore.searchQuery)) { item in
            ClipboardItemRow(item: item, clipboardStore: clipboardStore)
        }
        .listStyle(.plain)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let clipboardStore: ClipboardStore
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.body)
                    .lineLimit(2)
                
                Text(item.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Copy") {
                clipboardStore.copyItem(item)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardStore.copyItem(item)
        }
    }
}

// ClipboardStore implementation
@MainActor
class ClipboardStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    private var pasteboardChangeCount: Int = 0
    private var timer: Timer?
    
    init() {
        startMonitoring()
        loadHistory()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startMonitoring() {
        pasteboardChangeCount = NSPasteboard.general.changeCount
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                self.checkPasteboard()
            }
        }
    }
    
    private func checkPasteboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        if currentChangeCount != pasteboardChangeCount {
            pasteboardChangeCount = currentChangeCount
            
            if let string = NSPasteboard.general.string(forType: .string) {
                addToHistory(.text(string))
            }
        }
    }
    
    private func addToHistory(_ content: ClipboardContent) {
        let item = ClipboardItem(content: content, date: Date())
        
        // Remove duplicates
        history.removeAll { $0.content == content }
        
        // Add to beginning
        history.insert(item, at: 0)
        
        // Limit history size
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        
        saveHistory()
    }
    
    func copyItem(_ item: ClipboardItem) {
        switch item.content {
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
        
        // Move to top
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
    }
    
    func filteredHistory(for query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return history }
        
        let lowercasedQuery = query.lowercased()
        return history.filter { item in
            item.preview.lowercased().contains(lowercasedQuery)
        }
    }
    
    private func loadHistory() {
        // Load from UserDefaults or file
    }
    
    private func saveHistory() {
        // Save to UserDefaults or file
    }
}

struct ClipboardItem: Identifiable {
    let id = UUID()
    let content: ClipboardContent
    let date: Date
    
    var preview: String {
        switch content {
        case .text(let string):
            return string
        }
    }
    
    var icon: String {
        switch content {
        case .text:
            return "doc.text"
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

enum ClipboardContent: Equatable {
    case text(String)
    // Add more types as needed: image, file, etc.
}