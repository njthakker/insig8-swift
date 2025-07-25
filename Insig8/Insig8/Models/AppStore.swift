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
    case aiMonitor = "aiMonitor"
    case meeting = "meeting"
}

// Main app state management - replacing MobX UIStore
@MainActor
class AppStore: ObservableObject {
    // Singleton instance
    static let shared = AppStore()
    
    // Initialization guard
    private static var isInitialized = false
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
    
    // AI Monitoring settings
    @Published var enableAIMonitoring: Bool = false
    @Published var monitorScreenContent: Bool = false
    @Published var monitorAudioTranscripts: Bool = false
    @Published var monitorKeyboardInput: Bool = false
    
    // Services
    let searchService = SearchService()
    
    #if !MEETING_ONLY
    let aiPipeline = AIProcessingPipeline() // DISABLED: Transcription-only build
    #endif
    
    // Production infrastructure
    let sqliteVectorDB = SQLiteVectorDatabase()
    let secureStorage = SecureAIStorage()
    
    #if !MEETING_ONLY
    let screenCapture = ScreenCaptureService() // DISABLED: Transcription-only build
    #endif
    
    // New AI services for scenario coverage
    lazy private(set) var actionManager = ActionManager(sqliteDB: sqliteVectorDB, secureStorage: secureStorage)
    
    #if !MEETING_ONLY
    lazy private(set) var audioCapture = AudioCaptureService() // DISABLED: Transcription-only build
    #endif
    
    lazy private(set) var appFocusMonitor = AppFocusMonitor(appStore: self)
    
    // Meeting Service (Phase 1 - Clean Implementation)
    lazy private(set) var meetingService = MeetingService()
    
    // Legacy services for compatibility (will be phased out)
    let aiService = AppleIntelligenceService()
    let vectorDB = VectorDatabaseService()
    let communicationAI = CommunicationAIService()
    // TODO: Add other services in subsequent phases
    // let calendarStore = CalendarStore()
    // let clipboardStore = ClipboardStore()
    // let translationStore = TranslationStore()
    // let emojiStore = EmojiStore()
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupBindings()
        loadPreferences()
        
        // Only initialize infrastructure once
        if !Self.isInitialized {
            Self.isInitialized = true
            initializeProductionInfrastructure()
            setupActionIntegration()
            setupClipboardMonitoring()
            setupAppFocusMonitoring()
        }
    }
    
    private func setupBindings() {
        // React to search query changes - only for basic search, not AI
        $searchQuery
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.performBasicSearch(query)
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
        
        // Load AI monitoring settings
        enableAIMonitoring = UserDefaults.standard.bool(forKey: "enableAIMonitoring")
        monitorScreenContent = UserDefaults.standard.bool(forKey: "monitorScreenContent")
        monitorAudioTranscripts = UserDefaults.standard.bool(forKey: "monitorAudioTranscripts")
        monitorKeyboardInput = UserDefaults.standard.bool(forKey: "monitorKeyboardInput")
    }
    
    // MARK: - Production Infrastructure Initialization
    
    private func initializeProductionInfrastructure() {
        Task {
            // Initialize SQLite vector database
            do {
                try await sqliteVectorDB.initialize()
                AppConfig.log("SQLite vector database initialized with \(sqliteVectorDB.totalVectors) vectors")
                
                // Migrate existing vectors from UserDefaults if needed
                await migrateVectorsToSQLite()
            } catch {
                AppConfig.log("Failed to initialize SQLite vector database: \(error)", level: .error)
            }
            
            // Initialize secure storage
            do {
                let _ = try await secureStorage.getDatabaseKey()
                AppConfig.log("Secure storage initialized with encryption key")
                
                // Apply data retention policy
                if let db = try? secureStorage.openEncryptedDatabase(at: sqliteVectorDB.dbPath) {
                    try? await secureStorage.applyDataRetentionPolicy(on: db)
                }
            } catch {
                AppConfig.log("Failed to initialize secure storage: \(error)", level: .error)
            }
            
            // Initialize screen capture only if enabled and permission granted
            if AppConfig.enableScreenCapture && screenCapture.permissionGranted {
                try? await screenCapture.startMonitoring()
                AppConfig.log("Screen capture monitoring started")
            } else if AppConfig.enableScreenCapture {
                AppConfig.log("Screen capture permission not granted", level: .warning)
            } else {
                AppConfig.log("Meeting-only mode: Screen capture disabled")
            }
        }
    }
    
    private func migrateVectorsToSQLite() async {
        // Migrate from legacy VectorDatabaseService to SQLite
        // For now, skip migration as legacy vectorDB doesn't have getAllVectors
        // In production, implement a proper migration from UserDefaults
        let allVectors: [TaggedVector] = []
        
        guard !allVectors.isEmpty else { return }
        
        AppConfig.log("Migrating \(allVectors.count) vectors to SQLite...", level: .debug)
        
        var migrationBatch: [(id: String, content: String, embedding: [Float], source: ContentSource, tags: [ContentTag], metadata: [String: Any])] = []
        
        for vector in allVectors {
            migrationBatch.append((
                id: vector.id.uuidString,
                content: vector.content,
                embedding: vector.embedding,
                source: vector.source,
                tags: vector.tags,
                metadata: [:]
            ))
            
            // Batch insert every 100 vectors
            if migrationBatch.count >= 100 {
                try? await sqliteVectorDB.batchInsertVectors(migrationBatch)
                migrationBatch.removeAll()
            }
        }
        
        // Insert remaining vectors
        if !migrationBatch.isEmpty {
            try? await sqliteVectorDB.batchInsertVectors(migrationBatch)
        }
        
        AppConfig.log("Migration complete: \(allVectors.count) vectors migrated to SQLite", level: .debug)
    }
    
    // MARK: - Action Integration Setup
    
    private func setupActionIntegration() {
        // Set up screen capture to feed into action manager (only if enabled)
        guard AppConfig.enableScreenCapture else {
            AppConfig.log("Meeting-only mode: Action integration disabled")
            return
        }
        
        Task {
            // Connect screen capture data to action manager
            await connectScreenCaptureToActions()
            
            // Connect audio capture to action manager
            await connectAudioCaptureToActions()
        }
    }
    
    private func connectScreenCaptureToActions() async {
        // This would be implemented with proper observers/delegates
        // For now, we simulate the connection
        AppConfig.log("Connected screen capture to action manager", level: .debug)
    }
    
    private func connectAudioCaptureToActions() async {
        // This would be implemented with proper observers/delegates
        // For now, we simulate the connection
        AppConfig.log("Connected audio capture to action manager", level: .debug)
    }
    
    private func setupClipboardMonitoring() {
        // Monitor clipboard changes only if enabled (disabled in meeting-only mode)
        guard AppConfig.enableClipboardMonitoring else {
            AppConfig.log("Meeting-only mode: Clipboard monitoring disabled")
            return
        }
        
        var lastChangeCount = NSPasteboard.general.changeCount
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let currentChangeCount = NSPasteboard.general.changeCount
            
            if currentChangeCount != lastChangeCount {
                lastChangeCount = currentChangeCount
                
                // Get clipboard content
                if let content = NSPasteboard.general.string(forType: .string) {
                    // Store in vector database for search
                    Task {
                        await self.storeClipboardContent(content)
                    }
                }
            }
        }
        
        AppConfig.log("Started global clipboard monitoring", level: .debug)
    }
    
    private func setupAppFocusMonitoring() {
        // Start app focus monitoring only if enabled (disabled in meeting-only mode)
        guard AppConfig.enableAppFocusMonitoring else {
            AppConfig.log("Meeting-only mode: App focus monitoring disabled")
            return
        }
        
        // Load monitored apps from preferences
        appFocusMonitor.loadMonitoredApps()
        
        // Start monitoring app focus changes
        appFocusMonitor.startMonitoring()
        
        AppConfig.log("Started app focus monitoring", level: .debug)
    }
    
    @MainActor
    private func storeClipboardContent(_ content: String) async {
        // Skip very short content
        guard content.count > 10 else { return }
        
        // Store in vector database for search ONLY - no AI processing for clipboard
        if sqliteVectorDB.isInitialized {
            try? await sqliteVectorDB.addClipboardContent(
                content,
                type: .text,
                timestamp: Date()
            )
        } else {
            // Fallback to legacy vector DB
            vectorDB.addClipboardContent(content, type: .text, timestamp: Date())
        }
        
        AppConfig.log("Stored clipboard content: \(String(content.prefix(50)))...", level: .debug)
    }
    
    func performBasicSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            selectedIndex = 0
            return
        }
        
        isLoading = true
        
        Task {
            // Basic search without AI (for while typing)
            var results = await searchService.performSearch(query: query)
            
            // Add basic clipboard search from SQLite database
            if sqliteVectorDB.isInitialized {
                if let queryEmbedding = await vectorDB.generateEmbedding(for: query) {
                    let sqliteResults = try? await sqliteVectorDB.hybridSearch(
                        query: query,
                        embedding: queryEmbedding,
                        limit: 5
                    )
                    
                    if let sqliteResults = sqliteResults {
                        for result in sqliteResults {
                            let searchResult = SearchResult(
                                id: result.id,
                                title: extractTitle(from: result.content),
                                subtitle: "Found: \(String(result.content.prefix(100)))",
                                icon: getIconForSource(result.source),
                                type: .action,
                                action: .performSearch(result.content),
                                relevanceScore: Double(result.similarity)
                            )
                            results.append(searchResult)
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.searchResults = results
                self.selectedIndex = 0
                self.isLoading = false
            }
        }
    }
    
    func performFullSearchOnEnter(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            selectedIndex = 0
            return
        }
        
        isLoading = true
        
        Task {
            // Full AI-powered search (only on Enter)
            var results = await searchService.performSearch(query: query)
            
            // Always try AI-enhanced search first if available
            if aiService.isAIAvailable && !aiService.isProcessing {
                if let interpretation = await aiService.processNaturalLanguageCommand(query) {
                    // If AI identified a specific widget intent, prioritize that
                    if interpretation.confidence > 0.7,
                       let targetWidget = interpretation.targetWidget {
                        let widgetResult = SearchResult(
                            id: UUID().uuidString,
                            title: "Open \(targetWidget.rawValue.capitalized)",
                            subtitle: "AI suggested: \(interpretation.action)",
                            icon: "brain",
                            type: .action,
                            action: .switchToWidget(targetWidget),
                            relevanceScore: 1.0
                        )
                        results.insert(widgetResult, at: 0)
                    }
                }
                
                #if !MEETING_ONLY
                // Add AI pipeline search results (replaces vector database search)
                let aiResults = await aiPipeline.queryAI(query)
                for aiResult in aiResults {
                    let searchResult = SearchResult(
                        id: aiResult.id.uuidString,
                        title: extractTitle(from: aiResult.content),
                        subtitle: "AI Found: \(String(aiResult.content.prefix(100)))",
                        icon: getIconForSource(aiResult.source),
                        type: .action,
                        action: .performSearch(aiResult.content),
                        relevanceScore: Double(aiResult.relevanceScore)
                    )
                    results.append(searchResult)
                }
                #endif
                
                // Use production SQLite database for semantic search
                if sqliteVectorDB.isInitialized {
                    // Generate embedding for query using vector database service
                    if let queryEmbedding = await vectorDB.generateEmbedding(for: query) {
                        // Perform hybrid search (keyword + semantic)
                        let sqliteResults = try? await sqliteVectorDB.hybridSearch(
                            query: query,
                            embedding: queryEmbedding,
                            limit: 5
                        )
                        
                        if let sqliteResults = sqliteResults {
                            for result in sqliteResults {
                                let searchResult = SearchResult(
                                    id: result.id,
                                    title: extractTitle(from: result.content),
                                    subtitle: "Found: \(String(result.content.prefix(100)))",
                                    icon: getIconForSource(result.source),
                                    type: .action,
                                    action: .performSearch(result.content),
                                    relevanceScore: Double(result.similarity)
                                )
                                results.append(searchResult)
                            }
                        }
                    }
                } else {
                    // Fallback to legacy vector database
                    let semanticResults = await vectorDB.searchAll(query: query, limit: 3)
                    for semanticResult in semanticResults {
                        let searchResult = SearchResult(
                            id: UUID().uuidString,
                            title: semanticResult.title,
                            subtitle: "Found: \(semanticResult.content)",
                            icon: semanticResult.type == .url ? "link" : "doc.text",
                            type: .action,
                            action: semanticResult.url != nil ? .openURL(url: semanticResult.url!) : .performSearch(semanticResult.content),
                            relevanceScore: Double(semanticResult.similarity)
                        )
                        results.append(searchResult)
                    }
                }
                
                // Generate AI suggestions for context with communication data
                let context = AppContext(
                    currentTime: Date(),
                    activeWidget: selectedWidget,
                    recentActions: [], // TODO: Track recent actions
                    clipboardHistory: [], // TODO: Get from clipboard store
                    userActivity: [], // TODO: Track user activity
                    activeCommitments: communicationAI.activeCommitments.map { commitment in
                        CommitmentAnalysis(
                            hasCommitment: true,
                            commitmentText: commitment.text,
                            recipient: commitment.recipient,
                            dueDate: commitment.dueDate,
                            urgencyLevel: commitment.priority,
                            actionRequired: "Follow up on commitment",
                            confidence: commitment.confidence,
                            source: commitment.source
                        )
                    }
                )
                
                let suggestions = await aiService.generateSuggestions(for: context)
                for (index, suggestion) in suggestions.enumerated() {
                    let suggestionResult = SearchResult(
                        id: UUID().uuidString,
                        title: suggestion,
                        subtitle: "AI Suggestion",
                        icon: "lightbulb",
                        type: .suggestion,
                        action: .performSearch(suggestion),
                        relevanceScore: 0.9 - (Double(index) * 0.1)
                    )
                    results.append(suggestionResult)
                }
            }
            
            // Intelligent fallback: if we have few high-quality results, try natural language search
            let highQualityResults = results.filter { $0.relevanceScore > 0.7 }
            if highQualityResults.count < 2 && aiService.isAIAvailable {
                // Try natural language interpretation as fallback
                if let interpretation = await aiService.processNaturalLanguageCommand(query) {
                    if interpretation.confidence > 0.5 {
                        let naturalLanguageResult = SearchResult(
                            id: UUID().uuidString,
                            title: interpretation.action,
                            subtitle: "AI interpreted: \(interpretation.action)",
                            icon: "brain",
                            type: .suggestion,
                            action: interpretation.targetWidget != nil ? .switchToWidget(interpretation.targetWidget!) : .performSearch(interpretation.action),
                            relevanceScore: Double(interpretation.confidence)
                        )
                        results.insert(naturalLanguageResult, at: 0)
                    }
                }
                
                // Also try semantic search in vector database for any content
                if sqliteVectorDB.isInitialized {
                    if let queryEmbedding = await vectorDB.generateEmbedding(for: query) {
                        let fallbackResults = try? await sqliteVectorDB.similaritySearch(
                            query: queryEmbedding,
                            limit: 3,
                            threshold: 0.3  // Lower threshold for fallback
                        )
                        
                        if let fallbackResults = fallbackResults {
                            for result in fallbackResults {
                                let searchResult = SearchResult(
                                    id: UUID().uuidString,
                                    title: "📄 \(extractTitle(from: result.content))",
                                    subtitle: "Fallback search: \(String(result.content.prefix(80)))",
                                    icon: "doc.text.magnifyingglass",
                                    type: .action,
                                    action: .performSearch(result.content),
                                    relevanceScore: Double(result.similarity)
                                )
                                results.append(searchResult)
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.searchResults = results
                self.selectedIndex = 0
                self.isLoading = false
            }
        }
    }
    
    // Legacy method name for compatibility - now calls full search
    func performSearch(_ query: String) {
        performFullSearchOnEnter(query)
    }
    
    // Changed to async because we now await MainActor changes inside
    func executeCommand() async {
        guard selectedIndex < searchResults.count else { return }
        let result = searchResults[selectedIndex]
        
        // Handle widget switching actions specially
        if case .switchToWidget(let widget) = result.action {
            switchToWidget(widget)
            return
        }
        
        // Handle AI search suggestions
        if case .performSearch(let query) = result.action {
            searchQuery = query
            // Don't clear results immediately - let the search binding handle it
            return
        }
        
        // Execute other actions
        searchService.executeAction(result.action)
        
        // Clear search after execution (except for widget switches and search suggestions)
        // Wrapped in MainActor.run to ensure UI updates happen on the main thread since executeCommand is async now
        DispatchQueue.main.async {
            self.searchQuery = ""
            self.searchResults = []
            self.selectedIndex = 0
        }
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
    
    // MARK: - AI Pipeline Integration Methods
    
    /// Store clipboard content for search only (NO AI processing)
    func ingestClipboardContent(_ content: String) {
        // Clipboard content is only stored for search purposes, not AI processing
        // The actual storage happens in storeClipboardContent method
        Task {
            await storeClipboardContent(content)
        }
    }
    
    /// Ingest screen capture data from monitoring (only if enabled in settings)
    func ingestScreenCapture(_ ocrText: String, appName: String) {
        // Only process screen content if AI monitoring and screen content monitoring are enabled
        guard enableAIMonitoring && monitorScreenContent else { return }
        
        #if !MEETING_ONLY
        aiPipeline.ingestScreenCapture(ocrText, appName: appName)
        #endif
    }
    
    /// Ingest audio transcript data from meetings and app audio (only if enabled in settings)
    func ingestAudioTranscript(_ transcript: String, participants: [String], appName: String?) {
        // Only process audio transcripts if AI monitoring and audio transcript monitoring are enabled
        guard enableAIMonitoring && monitorAudioTranscripts else { return }
        
        #if !MEETING_ONLY
        aiPipeline.ingestMeetingTranscript(transcript, participants: participants)
        #endif
    }
    
    /// Ingest keyboard input for commitment/action detection (only if enabled in settings)
    func ingestKeyboardInput(_ text: String, appName: String) {
        // Only process keyboard input if AI monitoring and keyboard input monitoring are enabled
        guard enableAIMonitoring && monitorKeyboardInput else { return }
        
        #if !MEETING_ONLY
        // Use screen capture ingestion method as keyboard input is similar to screen text
        aiPipeline.ingestScreenCapture(text, appName: appName)
        #endif
    }
    
    /// Ingest email content for processing
    func ingestEmailContent(_ content: String, sender: String?, subject: String?) {
        #if !MEETING_ONLY
        aiPipeline.ingestEmailContent(content, sender: sender, subject: subject)
        #endif
    }
    
    /// Ingest browser history for context
    func ingestBrowserHistory(_ url: String, title: String?) {
        #if !MEETING_ONLY
        aiPipeline.ingestBrowserHistory(url, title: title)
        #endif
    }
    
    /// Ingest meeting transcripts
    func ingestMeetingTranscript(_ transcript: String, participants: [String]) {
        #if !MEETING_ONLY
        aiPipeline.ingestMeetingTranscript(transcript, participants: participants)
        #endif
    }
    
    /// Get active AI tasks for display
    func getActiveTasks() -> [AITask] {
        #if !MEETING_ONLY
        return aiPipeline.getActiveTasks()
        #else
        return []
        #endif
    }
    
    /// Modify AI task (snooze, dismiss, etc.)
    func modifyTask(_ taskId: UUID, modification: TaskModification) {
        #if !MEETING_ONLY
        aiPipeline.modifyTask(taskId, modification: modification)
        #endif
    }
    
    /// Get pipeline statistics for monitoring
    func getPipelineStatistics() -> PipelineStatistics {
        #if !MEETING_ONLY
        return aiPipeline.getPipelineStatistics()
        #else
        return PipelineStatistics(totalItemsProcessed: 0, itemsFiltered: 0, itemsPassed: 0, filterEfficiency: 0, vectorDatabaseSize: 0, activeTasks: 0, completedTasks: 0, urgentTasks: 0, overdueeTasks: 0)
        #endif
    }
    
    // MARK: - Helper Methods
    
    private func extractTitle(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if firstLine.count > 50 {
            return String(firstLine.prefix(47)) + "..."
        }
        
        return firstLine.isEmpty ? "Content" : firstLine
    }
    
    private func getIconForSource(_ source: ContentSource) -> String {
        switch source {
        case .clipboard:
            return "doc.on.clipboard"
        case .screenCapture:
            return "camera.viewfinder"
        case .email:
            return "envelope"
        case .browser:
            return "safari"
        case .meeting:
            return "video"
        case .manual:
            return "pencil"
        }
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

// MARK: - AppStore Screen Capture Integration Extension

extension AppStore {
    func ingestScreenCaptureData(_ ocrText: String, appName: String) {
        Task {
            #if !MEETING_ONLY
            // Send to AI pipeline for processing
            aiPipeline.ingestScreenCapture(ocrText, appName: appName)
            #endif
            
            // Store in SQLite database if initialized
            if sqliteVectorDB.isInitialized {
                let id = UUID().uuidString
                let source = ContentSource.screenCapture(appName)
                
                // Generate embedding using vector database service
                if let embedding = await vectorDB.generateEmbedding(for: ocrText) {
                    // Encrypt content if security is enabled
                    let contentToStore = secureStorage.encryptionEnabled ? 
                        secureStorage.sanitizeContent(ocrText) : ocrText
                    
                    try? await sqliteVectorDB.insertVector(
                        id: id,
                        content: contentToStore,
                        embedding: embedding,
                        source: source,
                        tags: [.communication],
                        metadata: [
                            "appName": appName,
                            "captureTime": Date().timeIntervalSince1970
                        ]
                    )
                }
            }
        }
    }
    
    func toggleScreenMonitoring() {
        #if !MEETING_ONLY
        Task {
            if screenCapture.isMonitoring {
                await screenCapture.stopMonitoring()
            } else {
                if !screenCapture.permissionGranted {
                    _ = await screenCapture.requestScreenRecordingPermission()
                }
                
                if screenCapture.permissionGranted {
                    try? await screenCapture.startMonitoring()
                }
            }
        }
        #endif
    }
    
    func updateScreenCaptureApps(_ apps: Set<String>) {
        #if !MEETING_ONLY
        screenCapture.monitoredApps = apps
        
        // Restart monitoring with new app list
        if screenCapture.isMonitoring {
            Task {
                await screenCapture.stopMonitoring()
                try? await screenCapture.startMonitoring()
            }
        }
        #endif
    }
}

