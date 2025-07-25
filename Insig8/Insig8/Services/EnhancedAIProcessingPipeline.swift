import SwiftUI
import Combine
import OSLog
import UserNotifications

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Enhanced AI Processing Pipeline with Orchestration

@MainActor
class EnhancedAIProcessingPipeline: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "EnhancedPipeline")
    
    // Core Components
    private let orchestrator: AgentOrchestrator
    private let vectorDB = EnhancedVectorDatabaseService()
    private let taskManager = AITaskManager()
    
    // Legacy agents for backward compatibility
    private let filteringAgent = ContentFilteringAgent()
    private let taggingAgent = ContentTaggingAgent()
    private let commitmentAgent = CommitmentDetectionAgent()
    private let followupAgent = FollowupTrackingAgent()
    private let contextAgent = ContextCorrelationAgent()
    private let reminderAgent = SmartReminderAgent()
    
    // Processing Queues
    private let processingQueue = DispatchQueue(label: "ai.processing.enhanced", qos: .utility)
    private let highPriorityQueue = DispatchQueue(label: "ai.priority.enhanced", qos: .userInitiated)
    
    // State Management
    @Published var isProcessing = false
    @Published var pendingItems: [ProcessingItem] = []
    @Published var activeTasks: [AITask] = []
    @Published var recentProcessedItems: [ProcessedItemResult] = []
    @Published var orchestratorResults: [ProcessingResult] = []
    
    // Model Enhancement
    private let modelCache = ModelCache()
    private let batchProcessor = BatchProcessor()
    
    init() {
        self.orchestrator = AgentOrchestrator()
        initializeEnhancedPipeline()
    }
    
    // MARK: - Enhanced Pipeline Initialization
    
    private func initializeEnhancedPipeline() {
        logger.info("Initializing Enhanced AI Processing Pipeline with Orchestration")
        
        // Start background processing
        startEnhancedBackgroundProcessing()
        
        // Initialize model optimizations
        initializeModelOptimizations()
        
        // Load persisted data
        loadPersistedTasks()
        
        logger.info("Enhanced pipeline initialization complete")
    }
    
    private func initializeModelOptimizations() {
        // Configure model caching
        modelCache.configure(maxCacheSize: 50, expirationTime: 3600) // 1 hour
        
        // Configure batch processing
        batchProcessor.configure(maxBatchSize: 5, maxWaitTime: 2.0)
        
        logger.info("Model optimizations configured")
    }
    
    // MARK: - Enhanced Data Ingestion
    
    /// Enhanced clipboard content processing with orchestration
    func ingestClipboardContent(_ content: String, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: content,
            source: .clipboard,
            timestamp: timestamp,
            priority: determinePriority(content)
        )
        
        enqueueForEnhancedProcessing(item)
    }
    
    /// Enhanced screen capture processing
    func ingestScreenCapture(_ ocrText: String, appName: String, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: ocrText,
            source: .screenCapture(appName),
            timestamp: timestamp,
            priority: .medium
        )
        
        enqueueForEnhancedProcessing(item)
    }
    
    /// Enhanced email content processing
    func ingestEmailContent(_ content: String, sender: String?, subject: String?, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: content,
            source: .email(sender: sender, subject: subject),
            timestamp: timestamp,
            priority: .high
        )
        
        enqueueForEnhancedProcessing(item)
    }
    
    /// Enhanced browser history processing
    func ingestBrowserHistory(_ url: String, title: String?, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: "\(title ?? "") \(url)",
            source: .browser(url: url, title: title),
            timestamp: timestamp,
            priority: .low
        )
        
        enqueueForEnhancedProcessing(item)
    }
    
    /// Enhanced meeting transcript processing
    func ingestMeetingTranscript(_ transcript: String, participants: [String], timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: transcript,
            source: .meeting(participants: participants),
            timestamp: timestamp,
            priority: .high
        )
        
        enqueueForEnhancedProcessing(item)
    }
    
    // MARK: - Enhanced Processing Engine
    
    private func enqueueForEnhancedProcessing(_ item: ProcessingItem) {
        pendingItems.append(item)
        
        let queue = item.priority == .urgent ? highPriorityQueue : processingQueue
        
        queue.async {
            Task { @MainActor in
                await self.processItemWithOrchestration(item)
            }
        }
    }
    
    private func startEnhancedBackgroundProcessing() {
        // Enhanced processing with batch support
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { @MainActor in
                await self.processPendingItemsEnhanced()
            }
        }
        
        // Cleanup timer
        Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { _ in
            Task { @MainActor in
                await self.performMaintenanceTasks()
            }
        }
    }
    
    private func processPendingItemsEnhanced() async {
        guard !isProcessing else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Process items in batches for efficiency
        let batchSize = batchProcessor.currentBatchSize
        let itemsToProcess = Array(pendingItems.prefix(batchSize))
        pendingItems.removeFirst(min(batchSize, pendingItems.count))
        
        if !itemsToProcess.isEmpty {
            await processBatchWithOrchestration(itemsToProcess)
        }
    }
    
    private func processBatchWithOrchestration(_ items: [ProcessingItem]) async {
        logger.info("Processing batch of \(items.count) items with orchestration")
        
        // Group items by priority for optimized processing
        let groupedItems = Dictionary(grouping: items, by: { $0.priority })
        
        // Process urgent items first
        for priority in [ProcessingPriority.urgent, .high, .medium, .low] {
            if let priorityItems = groupedItems[priority] {
                await processItemGroup(priorityItems, priority: priority)
            }
        }
    }
    
    private func processItemGroup(_ items: [ProcessingItem], priority: ProcessingPriority) async {
        for item in items {
            await processItemWithOrchestration(item)
            
            // Add small delay for urgent items to prevent overwhelming
            if priority == .urgent {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
    }
    
    private func processItemWithOrchestration(_ item: ProcessingItem) async {
        logger.info("Processing item with orchestration: \(item.source)")
        
        // Step 1: Legacy filtering for backward compatibility
        let shouldProcess = await filteringAgent.shouldProcessContent(item)
        
        guard shouldProcess else {
            logger.debug("Item filtered out: \(String(item.content.prefix(50)))")
            return
        }
        
        // Step 2: Enhanced processing with orchestration
        let userRequest = UserRequest(
            id: UUID(),
            query: item.content,
            context: [
                "source": item.source,
                "timestamp": item.timestamp,
                "priority": item.priority
            ],
            priority: item.priority
        )
        
        // Process through orchestrator
        let orchestratorResult = await orchestrator.processUserRequest(userRequest)
        orchestratorResults.append(orchestratorResult)
        
        // Also maintain legacy processing for compatibility
        await processItemLegacy(item)
        
        // Store orchestrator results
        if orchestratorResults.count > 20 {
            orchestratorResults.removeFirst()
        }
    }
    
    private func processItemLegacy(_ item: ProcessingItem) async {
        // Legacy processing pipeline for backward compatibility
        let tags = await taggingAgent.generateTags(for: item)
        
        // Store in Vector Database
        await vectorDB.storeContent(item.content, tags: tags, source: item.source, timestamp: item.timestamp)
        
        // Process with legacy agents
        if tags.contains(.commitment) {
            await commitmentAgent.processCommitment(item, tags: tags)
        }
        
        if tags.contains(.followup_required) {
            await followupAgent.trackFollowup(item, tags: tags)
        }
        
        if tags.contains(.urgent_action) {
            await reminderAgent.createUrgentReminder(item, tags: tags)
        }
        
        await contextAgent.correlateContext(item, tags: tags)
        
        // Store processed result
        let processedResult = ProcessedItemResult(
            id: item.id,
            originalContent: item.content,
            source: item.source,
            tags: tags,
            aiSummary: generateSummary(for: item.content, tags: tags),
            confidence: calculateConfidence(for: tags),
            processingTime: 0, // Would track actual time
            timestamp: Date()
        )
        
        recentProcessedItems.insert(processedResult, at: 0)
        
        if recentProcessedItems.count > 20 {
            recentProcessedItems.removeLast()
        }
        
        logger.info("Completed legacy processing for item: \(item.id)")
    }
    
    // MARK: - Enhanced Query Interface
    
    func queryAI(_ query: String) async -> [AIQueryResult] {
        logger.info("Processing enhanced AI query: \(query)")
        
        // Try orchestrator first for intelligent processing
        let userRequest = UserRequest(
            id: UUID(),
            query: query,
            context: [:],
            priority: .medium
        )
        
        let orchestratorResult = await orchestrator.processUserRequest(userRequest)
        
        // Convert orchestrator results to query results
        var results: [AIQueryResult] = []
        
        // Add orchestrator-based results
        for (taskId, response) in orchestratorResult.results {
            if response.status == .success {
                results.append(AIQueryResult(
                    id: taskId,
                    content: response.results.description,
                    source: .manual,
                    tags: [],
                    timestamp: Date(),
                    relevanceScore: Float(response.confidence),
                    type: .contextMatch
                ))
            }
        }
        
        // Fallback to legacy search if no orchestrator results
        if results.isEmpty {
            return await queryAILegacy(query)
        }
        
        return results
    }
    
    private func queryAILegacy(_ query: String) async -> [AIQueryResult] {
        // Legacy query processing
        let vectorResults = await vectorDB.intelligentSearch(query: query, limit: 10)
        let taskResults = taskManager.searchTasks(query: query)
        
        var combinedResults: [AIQueryResult] = []
        
        // Add vector database results
        for result in vectorResults {
            combinedResults.append(AIQueryResult(
                id: UUID(),
                content: result.content,
                source: result.source,
                tags: result.tags,
                timestamp: result.timestamp,
                relevanceScore: result.similarity,
                type: .vectorMatch
            ))
        }
        
        // Add task results
        for task in taskResults {
            combinedResults.append(AIQueryResult(
                id: task.id,
                content: task.description,
                source: task.source,
                tags: task.tags,
                timestamp: task.createdDate,
                relevanceScore: task.relevanceScore,
                type: .taskMatch
            ))
        }
        
        combinedResults.sort { $0.relevanceScore > $1.relevanceScore }
        return Array(combinedResults.prefix(8))
    }
    
    // MARK: - Enhanced Task Management
    
    func getActiveTasks() -> [AITask] {
        return taskManager.getActiveTasks()
    }
    
    func getOrchestratorResults() -> [ProcessingResult] {
        return orchestratorResults
    }
    
    func getAgentStatuses() -> [AgentStatus] {
        return orchestrator.getAgentStatuses()
    }
    
    func modifyTask(_ taskId: UUID, modification: TaskModification) {
        taskManager.modifyTask(taskId, modification: modification)
    }
    
    func dismissTask(_ taskId: UUID) {
        taskManager.dismissTask(taskId)
    }
    
    func snoozeTask(_ taskId: UUID, until: Date) {
        taskManager.snoozeTask(taskId, until: until)
    }
    
    // MARK: - Model Optimization
    
    private func performMaintenanceTasks() async {
        // Clear old cache entries
        modelCache.cleanup()
        
        // Optimize vector database
        await vectorDB.optimize()
        
        // Clean up old results
        if orchestratorResults.count > 50 {
            orchestratorResults = Array(orchestratorResults.suffix(30))
        }
        
        if recentProcessedItems.count > 50 {
            recentProcessedItems = Array(recentProcessedItems.prefix(30))
        }
        
        logger.info("Maintenance tasks completed")
    }
    
    // MARK: - Enhanced Statistics
    
    func getEnhancedPipelineStatistics() -> EnhancedPipelineStatistics {
        let legacyStats = getPipelineStatistics()
        _ = getOrchestratorStatistics()
        
        return EnhancedPipelineStatistics(
            legacyStats: legacyStats,
            orchestratorProcessedRequests: orchestratorResults.count,
            successfulOrchestratorRequests: orchestratorResults.filter { $0.status == .success }.count,
            averageOrchestratorConfidence: calculateAverageConfidence(),
            modelCacheHitRate: modelCache.hitRate,
            batchProcessingEfficiency: batchProcessor.efficiency
        )
    }
    
    private func getOrchestratorStatistics() -> [String: Any] {
        return [
            "totalRequests": orchestratorResults.count,
            "successfulRequests": orchestratorResults.filter { $0.status == .success }.count,
            "partialFailures": orchestratorResults.filter { $0.status == .partialFailure }.count,
            "failures": orchestratorResults.filter { $0.status == .failure }.count
        ]
    }
    
    private func calculateAverageConfidence() -> Double {
        let allConfidences = orchestratorResults.flatMap { result in
            result.results.values.map { $0.confidence }
        }
        
        guard !allConfidences.isEmpty else { return 0.0 }
        return allConfidences.reduce(0, +) / Double(allConfidences.count)
    }
    
    // MARK: - Utility Methods (Legacy compatibility)
    
    private func determinePriority(_ content: String) -> ProcessingPriority {
        let lowercased = content.lowercased()
        
        if lowercased.contains("urgent") || lowercased.contains("asap") {
            return .urgent
        } else if lowercased.contains("important") || lowercased.contains("deadline") {
            return .high
        } else if lowercased.contains("follow up") || lowercased.contains("@") {
            return .medium
        } else {
            return .low
        }
    }
    
    private func loadPersistedTasks() {
        activeTasks = taskManager.loadPersistedTasks()
    }
    
    private func generateSummary(for content: String, tags: [ContentTag]) -> String {
        if content.count < 50 {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let sentences = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? content
        
        if firstSentence.count > 100 {
            return String(firstSentence.prefix(97)) + "..."
        }
        
        return firstSentence
    }
    
    private func calculateConfidence(for tags: [ContentTag]) -> Double {
        var confidence = 0.5
        
        if tags.contains(.urgent_action) || tags.contains(.commitment) {
            confidence += 0.3
        }
        
        if tags.contains(.important) {
            confidence += 0.2
        }
        
        return min(confidence, 1.0)
    }
    
    // Legacy method for backward compatibility
    func getPipelineStatistics() -> PipelineStatistics {
        let filteringStats = filteringAgent.getFilteringStats()
        let taskStats = taskManager.getTaskStatistics()
        let vectorStats = vectorDB.vectorCount
        
        return PipelineStatistics(
            totalItemsProcessed: filteringStats.totalProcessed,
            itemsFiltered: filteringStats.filtered,
            itemsPassed: filteringStats.passed,
            filterEfficiency: filteringStats.filterRate,
            vectorDatabaseSize: vectorStats,
            activeTasks: taskStats.totalActive,
            completedTasks: taskStats.totalCompleted,
            urgentTasks: taskStats.urgent,
            overdueeTasks: taskStats.overdue
        )
    }
    
    func resetPipelineStatistics() {
        filteringAgent.resetStats()
        orchestratorResults.removeAll()
        recentProcessedItems.removeAll()
        modelCache.clear()
        logger.info("Enhanced pipeline statistics reset")
    }
}

// MARK: - Model Optimization Components

class ModelCache {
    private var cache: [String: CachedResult] = [:]
    private var maxCacheSize = 50
    private var expirationTime: TimeInterval = 3600
    private var hitCount = 0
    private var missCount = 0
    
    func configure(maxCacheSize: Int, expirationTime: TimeInterval) {
        self.maxCacheSize = maxCacheSize
        self.expirationTime = expirationTime
    }
    
    func get(key: String) -> Any? {
        guard let cached = cache[key],
              Date().timeIntervalSince(cached.timestamp) < expirationTime else {
            missCount += 1
            return nil
        }
        
        hitCount += 1
        return cached.result
    }
    
    func set(key: String, value: Any) {
        if cache.count >= maxCacheSize {
            // Remove oldest entry
            let oldestKey = cache.min { $0.value.timestamp < $1.value.timestamp }?.key
            if let key = oldestKey {
                cache.removeValue(forKey: key)
            }
        }
        
        cache[key] = CachedResult(result: value, timestamp: Date())
    }
    
    func cleanup() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < expirationTime }
    }
    
    func clear() {
        cache.removeAll()
        hitCount = 0
        missCount = 0
    }
    
    var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }
}

struct CachedResult {
    let result: Any
    let timestamp: Date
}

class BatchProcessor {
    private var maxBatchSize = 5
    private var maxWaitTime: TimeInterval = 2.0
    private var processedBatches = 0
    private var totalItems = 0
    
    func configure(maxBatchSize: Int, maxWaitTime: TimeInterval) {
        self.maxBatchSize = maxBatchSize
        self.maxWaitTime = maxWaitTime
    }
    
    var currentBatchSize: Int {
        return maxBatchSize
    }
    
    func recordBatch(itemCount: Int) {
        processedBatches += 1
        totalItems += itemCount
    }
    
    var efficiency: Double {
        return processedBatches > 0 ? Double(totalItems) / Double(processedBatches) : 0.0
    }
}

// MARK: - Enhanced Statistics

struct EnhancedPipelineStatistics {
    let legacyStats: PipelineStatistics
    let orchestratorProcessedRequests: Int
    let successfulOrchestratorRequests: Int
    let averageOrchestratorConfidence: Double
    let modelCacheHitRate: Double
    let batchProcessingEfficiency: Double
}