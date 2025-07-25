import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

struct ClipboardWidgetView: View {
    @StateObject private var clipboardStore = ClipboardStore()
    @EnvironmentObject var appStore: AppStore
    @State private var aiEnhancements: [String: ClipboardEnhancement] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            ClipboardHeaderView(clipboardStore: clipboardStore)
            
            Divider()
            
            // Content
            if clipboardStore.history.isEmpty {
                EmptyClipboardView()
            } else {
                ClipboardHistoryList(
                    clipboardStore: clipboardStore,
                    aiEnhancements: aiEnhancements,
                    aiService: appStore.aiService
                )
                .onReceive(clipboardStore.$history) { history in
                    // Add relevant items to vector database for semantic search (legacy)
                    addItemsToVectorDatabase(history)
                    // Send to AI pipeline for comprehensive processing
                    ingestToAIPipeline(history)
                    // Only enhance communication-related content (legacy)
                    enhanceRelevantClipboardItems(history)
                }
            }
        }
    }
    
    // AI Pipeline Integration
    private func ingestToAIPipeline(_ history: [ClipboardItem]) {
        // Only process the most recent item to avoid flooding the pipeline
        guard let latestItem = history.first else { return }
        
        switch latestItem.content {
        case .text(let content) where content.count > 10:
            // Send text content to AI pipeline for processing
            appStore.ingestClipboardContent(content)
        case .url(let urlString):
            // Send URL content with title extraction if possible
            appStore.ingestClipboardContent("URL: \(urlString)")
        default:
            break
        }
    }
    
    // Vector Database Integration (Legacy - kept for compatibility)
    private func addItemsToVectorDatabase(_ history: [ClipboardItem]) {
        // Use the vector database from appStore instead of creating a separate instance
        let vectorDB = appStore.vectorDB
        
        for item in history.prefix(5) { // Add recent items to vector DB
            switch item.content {
            case .url(let urlString):
                vectorDB.addURL(urlString, title: nil, description: nil, timestamp: item.date)
            case .text(let content) where content.count > 50:
                // Only store meaningful text content in vector DB
                vectorDB.addClipboardContent(content, type: .text, timestamp: item.date)
            default:
                break
            }
        }
    }
    
    // AI Enhancement Logic (Only for Communications)
    private func enhanceRelevantClipboardItems(_ history: [ClipboardItem]) {
        guard appStore.aiService.isAIAvailable && !appStore.aiService.isProcessing else { return }
        
        // Only enhance the most recent item to avoid concurrent calls
        guard let latestItem = history.first else { return }
        let itemId = latestItem.id.uuidString
        
        // Skip if already enhanced
        guard aiEnhancements[itemId] == nil else { return }
        
        // Only enhance communication-related content
        if case .text(let content) = latestItem.content {
            // Check if content looks like communication (email, message, etc.)
            if isCommuncationContent(content) {
                Task {
                    // Add a small delay to prevent rapid-fire calls
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    if let enhancement = await appStore.aiService.enhanceClipboardContent(content) {
                        await MainActor.run {
                            aiEnhancements[itemId] = enhancement
                        }
                    }
                }
            }
        }
    }
    
    // Check if content is communication-related
    private func isCommuncationContent(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        let communicationKeywords = [
            "from:", "to:", "subject:", "dear", "hi ", "hello", "regards", "sincerely",
            "meeting", "call", "discuss", "follow up", "agenda", "action item",
            "slack", "teams", "email", "message", "@", "reply", "response"
        ]
        
        return communicationKeywords.contains { lowercased.contains($0) } ||
               content.contains("@") && content.contains(".") || // Email-like
               content.count > 100 && content.contains("?") // Long text with questions
    }
}

struct ClipboardHeaderView: View {
    @ObservedObject var clipboardStore: ClipboardStore
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard")
                    .font(.headline)
                Text("Clipboard History")
                    .font(.headline)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("\(clipboardStore.history.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { clipboardStore.clearHistory() }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Clear all clipboard history")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct EmptyClipboardView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Clipboard is empty")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Copy something to see it here")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ClipboardHistoryList: View {
    @ObservedObject var clipboardStore: ClipboardStore
    @EnvironmentObject var appStore: AppStore
    let aiEnhancements: [String: ClipboardEnhancement]
    let aiService: AppleIntelligenceService
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(clipboardStore.filteredHistory(for: appStore.searchQuery)) { item in
                    ClipboardItemRow(
                        item: item, 
                        clipboardStore: clipboardStore,
                        enhancement: aiEnhancements[item.id.uuidString],
                        aiService: aiService
                    )
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let clipboardStore: ClipboardStore
    let enhancement: ClipboardEnhancement?
    let aiService: AppleIntelligenceService
    @State private var isHovered = false
    @State private var showAIInsights = false
    @State private var isExpanded = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                if isExpanded {
                    ScrollView {
                        Text(item.fullContent)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 120) // Max height constraint
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                } else {
                    Text(item.preview)
                        .font(.body)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                // AI Enhancement Summary
                if let enhancement = enhancement {
                    HStack {
                        Image(systemName: "brain")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(enhancement.summary)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(showAIInsights ? nil : 1)
                    }
                    .padding(.top, 2)
                }
                
                HStack {
                    Text(item.timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let enhancement = enhancement {
                        Text("• \(enhancement.contentType.rawValue.capitalized)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else if case .image = item.content {
                        Text("• Image")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if case .file = item.content {
                        Text("• File")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if case .url = item.content {
                        Text("• URL")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // AI insight toggle
                    if enhancement != nil && aiService.isAIAvailable {
                        Button(action: { showAIInsights.toggle() }) {
                            Image(systemName: showAIInsights ? "brain.filled" : "brain")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .help(showAIInsights ? "Hide AI insights" : "Show AI insights")
                    }
                }
            }
            
            Spacer()
            
            // Actions
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Collapse" : "Expand")
                    
                    Button(action: { clipboardStore.copyItem(item) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
                    
                    // AI-powered suggested actions
                    if let enhancement = enhancement {
                        ForEach(Array(enhancement.suggestedActions.prefix(2).enumerated()), id: \.offset) { _, action in
                            Button(action: { 
                                executeAIAction(action, for: item)
                            }) {
                                Image(systemName: iconForAction(action))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.borderless)
                            .help(action)
                        }
                    }
                    
                    Button(action: { clipboardStore.deleteItem(item) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete from history")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpanded {
                // If expanded, collapse it
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded = false
                }
            } else {
                // If collapsed, expand it
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded = true
                }
            }
        }
        .onTapGesture(count: 2) {
            // Double tap to copy
            clipboardStore.copyItem(item)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var iconColor: Color {
        switch item.content {
        case .text:
            return .blue
        case .image:
            return .green
        case .file:
            return .orange
        case .url:
            return .purple
        }
    }
    
    // AI Action helpers
    private func executeAIAction(_ action: String, for item: ClipboardItem) {
        let lowercaseAction = action.lowercased()
        
        switch item.content {
        case .text(let text):
            if lowercaseAction.contains("search") {
                if let url = URL(string: "https://www.google.com/search?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    NSWorkspace.shared.open(url)
                }
            } else if lowercaseAction.contains("save") {
                // Save to a file
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.plainText]
                savePanel.nameFieldStringValue = "clipboard_text.txt"
                if savePanel.runModal() == .OK, let url = savePanel.url {
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        case .url(let urlString):
            if lowercaseAction.contains("open") {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        case .file(let path):
            if lowercaseAction.contains("open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .image(_):
            if lowercaseAction.contains("save") {
                // Could implement image saving
                print("Save image action not yet implemented")
            }
        }
    }
    
    private func iconForAction(_ action: String) -> String {
        let lowercaseAction = action.lowercased()
        
        if lowercaseAction.contains("search") {
            return "magnifyingglass"
        } else if lowercaseAction.contains("save") {
            return "square.and.arrow.down"
        } else if lowercaseAction.contains("open") {
            return "arrow.up.right.square"
        } else if lowercaseAction.contains("copy") {
            return "doc.on.doc"
        } else {
            return "star"
        }
    }
}

// Enhanced ClipboardStore with rich content support and persistence
@MainActor
class ClipboardStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    private var pasteboardChangeCount: Int = 0
    private var timer: Timer?
    private let maxHistoryItems = 100
    
    init() {
        loadHistory()
        startMonitoring()
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
        print("Clipboard monitoring started successfully")
    }
    
    private func checkPasteboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        if currentChangeCount != pasteboardChangeCount {
            pasteboardChangeCount = currentChangeCount
            
            let pasteboard = NSPasteboard.general
            
            // Check for different content types in order of preference
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let firstURL = fileURLs.first {
                if firstURL.isFileURL {
                    addToHistory(.file(firstURL.path))
                } else {
                    addToHistory(.url(firstURL.absoluteString))
                }
            } else if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
                      let imageData = image.tiffRepresentation {
                addToHistory(.image(imageData))
            } else if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Check if string is a URL
                if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), 
                   url.scheme != nil {
                    addToHistory(.url(string.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    addToHistory(.text(string))
                }
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
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        
        saveHistory()
    }
    
    func copyItem(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file(let path):
            let url = URL(fileURLWithPath: path)
            pasteboard.writeObjects([url as NSURL])
        case .url(let urlString):
            pasteboard.setString(urlString, forType: .string)
            if let url = URL(string: urlString) {
                pasteboard.writeObjects([url as NSURL])
            }
        }
        
        // Move to top of history
        history.removeAll { $0.id == item.id }
        let updatedItem = ClipboardItem(content: item.content, date: Date())
        history.insert(updatedItem, at: 0)
        saveHistory()
    }
    
    func filteredHistory(for query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return history }
        
        let lowercasedQuery = query.lowercased()
        return history.filter { item in
            item.preview.lowercased().contains(lowercasedQuery)
        }
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    func deleteItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    private func loadHistory() {
        do {
            guard let data = UserDefaults.standard.data(forKey: "ClipboardHistory") else {
                print("No existing clipboard history found")
                return
            }
            
            let decodedHistory = try JSONDecoder().decode([ClipboardItemData].self, from: data)
            self.history = decodedHistory.compactMap { itemData in
                ClipboardItem(content: itemData.content, date: itemData.date)
            }
            print("Loaded \(self.history.count) clipboard items from history")
        } catch {
            print("Failed to load clipboard history: \(error.localizedDescription)")
            self.history = []
        }
    }
    
    private func saveHistory() {
        let itemData = history.map { ClipboardItemData(content: $0.content, date: $0.date) }
        
        if let encoded = try? JSONEncoder().encode(itemData) {
            UserDefaults.standard.set(encoded, forKey: "ClipboardHistory")
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let content: ClipboardContent
    let date: Date
    
    var preview: String {
        switch content {
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            // Truncate for preview
            if trimmed.count > 150 {
                return String(trimmed.prefix(150)) + "..."
            }
            return trimmed
        case .image(_):
            return "Image from clipboard"
        case .file(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .url(let urlString):
            return urlString
        }
    }
    
    var fullContent: String {
        switch content {
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image(_):
            return "Image from clipboard - Cannot display text content"
        case .file(let path):
            return "File: \(path)"
        case .url(let urlString):
            return urlString
        }
    }
    
    var icon: String {
        switch content {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .url:
            return "link"
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

// Helper struct for persistence
struct ClipboardItemData: Codable {
    let content: ClipboardContent
    let date: Date
}

enum ClipboardContent: Equatable, Codable {
    case text(String)
    case image(Data)
    case file(String) // File path
    case url(String)
    
    var description: String {
        switch self {
        case .text(let string):
            return string
        case .image(_):
            return "[Image]"
        case .file(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .url(let urlString):
            return urlString
        }
    }
}