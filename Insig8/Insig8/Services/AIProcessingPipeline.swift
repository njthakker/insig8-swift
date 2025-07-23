import SwiftUI
import Combine
import OSLog
import UserNotifications

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Processing Pipeline Architecture
@MainActor
class AIProcessingPipeline: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "Pipeline")
    
    // AI Agents (Pipeline order matters!)
    private let filteringAgent = ContentFilteringAgent()  // FIRST: Filter out irrelevant content
    private let taggingAgent = ContentTaggingAgent()      // SECOND: Tag relevant content
    private let commitmentAgent = CommitmentDetectionAgent()
    private let followupAgent = FollowupTrackingAgent()
    private let contextAgent = ContextCorrelationAgent()
    private let reminderAgent = SmartReminderAgent()
    
    // Storage Systems
    private let vectorDB = EnhancedVectorDatabaseService()
    private let taskManager = AITaskManager()
    
    // Processing Queues
    private let processingQueue = DispatchQueue(label: "ai.processing", qos: .utility)
    private let highPriorityQueue = DispatchQueue(label: "ai.priority", qos: .userInitiated)
    
    // State Management
    @Published var isProcessing = false
    @Published var pendingItems: [ProcessingItem] = []
    @Published var activeTasks: [AITask] = []
    @Published var recentProcessedItems: [ProcessedItemResult] = []
    
    init() {
        initializePipeline()
    }
    
    // MARK: - Pipeline Initialization
    
    private func initializePipeline() {
        logger.info("Initializing AI Processing Pipeline")
        
        // Start background processing
        startBackgroundProcessing()
        
        // Initialize agents
        initializeAgents()
        
        // Load persisted data
        loadPersistedTasks()
    }
    
    private func initializeAgents() {
        // Initialize agents - delegates not needed for current implementation
        logger.info("AI agents initialized")
    }
    
    // MARK: - Data Ingestion Entry Points
    
    /// Process clipboard content in background
    func ingestClipboardContent(_ content: String, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: content,
            source: .clipboard,
            timestamp: timestamp,
            priority: determinePriority(content)
        )
        
        enqueueForProcessing(item)
    }
    
    /// Process screen capture data
    func ingestScreenCapture(_ ocrText: String, appName: String, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: ocrText,
            source: .screenCapture(appName),
            timestamp: timestamp,
            priority: .medium
        )
        
        enqueueForProcessing(item)
    }
    
    /// Process email content
    func ingestEmailContent(_ content: String, sender: String?, subject: String?, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: content,
            source: .email(sender: sender, subject: subject),
            timestamp: timestamp,
            priority: .high // Emails are high priority
        )
        
        enqueueForProcessing(item)
    }
    
    /// Process browser history
    func ingestBrowserHistory(_ url: String, title: String?, timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: "\(title ?? "") \(url)",
            source: .browser(url: url, title: title),
            timestamp: timestamp,
            priority: .low
        )
        
        enqueueForProcessing(item)
    }
    
    /// Process meeting transcript
    func ingestMeetingTranscript(_ transcript: String, participants: [String], timestamp: Date = Date()) {
        let item = ProcessingItem(
            id: UUID(),
            content: transcript,
            source: .meeting(participants: participants),
            timestamp: timestamp,
            priority: .high
        )
        
        enqueueForProcessing(item)
    }
    
    // MARK: - Background Processing Engine
    
    private func enqueueForProcessing(_ item: ProcessingItem) {
        pendingItems.append(item)
        
        let queue = item.priority == .urgent ? highPriorityQueue : processingQueue
        
        queue.async {
            Task { @MainActor in
                await self.processItem(item)
            }
        }
    }
    
    private func startBackgroundProcessing() {
        // Process pending items every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                await self.processPendingItems()
            }
        }
    }
    
    private func processPendingItems() async {
        guard !isProcessing else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let itemsToProcess = Array(pendingItems.prefix(5)) // Batch process
        pendingItems.removeFirst(min(5, pendingItems.count))
        
        for item in itemsToProcess {
            await processItem(item)
        }
    }
    
    private func processItem(_ item: ProcessingItem) async {
        logger.info("Processing item: \(item.source)")
        
        // Step 1: CONTENT FILTERING - First stage filter
        let shouldProcess = await filteringAgent.shouldProcessContent(item)
        
        guard shouldProcess else {
            logger.debug("Item filtered out: \(String(item.content.prefix(50)))")
            return
        }
        
        // Step 2: Content Tagging (only for relevant content)
        let tags = await taggingAgent.generateTags(for: item)
        
        // Step 3: Store in Vector Database with tags
        await vectorDB.storeContent(item.content, tags: tags, source: item.source, timestamp: item.timestamp)
        
        // Step 4: Agent Processing based on tags
        if tags.contains(.commitment) {
            await commitmentAgent.processCommitment(item, tags: tags)
        }
        
        if tags.contains(.followup_required) {
            await followupAgent.trackFollowup(item, tags: tags)
        }
        
        if tags.contains(.urgent_action) {
            await reminderAgent.createUrgentReminder(item, tags: tags)
        }
        
        // Step 5: Context Correlation
        await contextAgent.correlateContext(item, tags: tags)
        
        // Step 6: Store processed result for monitoring
        let processedResult = ProcessedItemResult(
            id: item.id,
            originalContent: item.content,
            source: item.source,
            tags: tags,
            aiSummary: generateSummary(for: item.content, tags: tags),
            confidence: calculateConfidence(for: tags),
            processingTime: CFAbsoluteTimeGetCurrent() - CFAbsoluteTimeGetCurrent(), // Would track actual time
            timestamp: Date()
        )
        
        recentProcessedItems.insert(processedResult, at: 0)
        
        // Keep only last 20 items
        if recentProcessedItems.count > 20 {
            recentProcessedItems.removeLast()
        }
        
        logger.info("Completed processing item: \(item.id)")
    }
    
    // MARK: - Natural Language Query Interface
    
    func queryAI(_ query: String) async -> [AIQueryResult] {
        logger.info("Processing AI query: \(query)")
        
        // Search vector database with intelligent semantic matching
        let vectorResults = await vectorDB.intelligentSearch(query: query, limit: 10)
        
        // Search active tasks
        let taskResults = taskManager.searchTasks(query: query)
        
        // Combine and rank results
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
        
        // Sort by relevance
        combinedResults.sort { $0.relevanceScore > $1.relevanceScore }
        
        return Array(combinedResults.prefix(8)) // Return top 8 results
    }
    
    // MARK: - Task Management Interface
    
    func getActiveTasks() -> [AITask] {
        return taskManager.getActiveTasks()
    }
    
    func getPendingItems() -> [ProcessingItem] {
        return pendingItems
    }
    
    func getRecentProcessedItems() -> [ProcessedItemResult] {
        return recentProcessedItems
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
    
    // MARK: - Utility Methods
    
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
        // Generate a simple AI summary based on content length and tags
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
        // Simple confidence calculation based on tag types
        var confidence = 0.5 // Base confidence
        
        if tags.contains(.urgent_action) || tags.contains(.commitment) {
            confidence += 0.3
        }
        
        if tags.contains(.important) {
            confidence += 0.2
        }
        
        return min(confidence, 1.0)
    }
    
    // MARK: - Pipeline Statistics and Monitoring
    
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
    
    func getAgentStatus() -> [AgentStatus] {
        return [
            AgentStatus(
                name: "Content Filtering",
                type: .filtering,
                isActive: true,
                lastActivity: Date(),
                processedCount: filteringAgent.getFilteringStats().totalProcessed
            ),
            AgentStatus(
                name: "Content Tagging",
                type: .tagging,
                isActive: true,
                lastActivity: Date(),
                processedCount: 0 // Would need to add tracking
            ),
            AgentStatus(
                name: "Commitment Detection",
                type: .commitment,
                isActive: true,
                lastActivity: Date(),
                processedCount: 0 // Would need to add tracking
            ),
            AgentStatus(
                name: "Followup Tracking",
                type: .followup,
                isActive: true,
                lastActivity: Date(),
                processedCount: 0 // Would need to add tracking
            ),
            AgentStatus(
                name: "Context Correlation",
                type: .context,
                isActive: true,
                lastActivity: Date(),
                processedCount: 0 // Would need to add tracking
            ),
            AgentStatus(
                name: "Smart Reminders",
                type: .reminder,
                isActive: true,
                lastActivity: Date(),
                processedCount: 0 // Would need to add tracking
            )
        ]
    }
    
    func resetPipelineStatistics() {
        filteringAgent.resetStats()
        logger.info("Pipeline statistics reset")
    }
}

// MARK: - Pipeline Delegate Protocol

protocol AIAgentDelegate: AnyObject {
    func agentDidCreateTask(_ task: AITask)
    func agentDidUpdateTask(_ taskId: UUID, updates: [String: Any])
    func agentDidCompleteProcessing(_ agentType: AIAgentType)
}

extension AIProcessingPipeline: AIAgentDelegate {
    func agentDidCreateTask(_ task: AITask) {
        activeTasks.append(task)
        taskManager.addTask(task)
        
        // Schedule notification if needed
        if task.priority == .urgent {
            scheduleUrgentNotification(for: task)
        }
    }
    
    func agentDidUpdateTask(_ taskId: UUID, updates: [String: Any]) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            activeTasks[index].applyUpdates(updates)
            taskManager.updateTask(taskId, updates: updates)
        }
    }
    
    func agentDidCompleteProcessing(_ agentType: AIAgentType) {
        logger.info("Agent completed processing: \(agentType)")
    }
    
    private func scheduleUrgentNotification(for task: AITask) {
        let content = UNMutableNotificationContent()
        content.title = "Urgent Action Required"
        content.body = task.description
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: nil // Immediate notification
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Data Models

struct ProcessingItem: Identifiable {
    let id: UUID
    let content: String
    let source: ContentSource
    let timestamp: Date
    let priority: ProcessingPriority
}

enum ContentSource: Codable, CustomStringConvertible {
    case clipboard
    case screenCapture(String) // app name
    case email(sender: String?, subject: String?)
    case browser(url: String, title: String?)
    case meeting(participants: [String])
    case manual
    
    var description: String {
        switch self {
        case .clipboard:
            return "clipboard"
        case .screenCapture(let app):
            return "screen(\(app))"
        case .email(let sender, let subject):
            return "email(\(sender ?? "unknown"), \(subject ?? "no subject"))"
        case .browser(let url, let title):
            return "browser(\(title ?? url))"
        case .meeting(let participants):
            return "meeting(\(participants.joined(separator: ", ")))"
        case .manual:
            return "manual"
        }
    }
}

enum ProcessingPriority: Int, Codable {
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4
}

enum ContentTag: String, Codable, CaseIterable {
    case commitment = "commitment"
    case followup_required = "followup_required"
    case urgent_action = "urgent_action"
    case reminder = "reminder"
    case action_item = "action_item"
    case meeting_notes = "meeting_notes"
    case email_thread = "email_thread"
    case code_snippet = "code_snippet"
    case url_link = "url_link"
    case contact_info = "contact_info"
    case deadline = "deadline"
    case question = "question"
    case important = "important"
    case communication = "communication"
    case clipboard = "clipboard"
    case task = "task"
}

struct AIQueryResult: Identifiable {
    let id: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let timestamp: Date
    let relevanceScore: Float
    let type: QueryResultType
}

enum QueryResultType {
    case vectorMatch
    case taskMatch
    case contextMatch
}

enum AIAgentType: String, CustomStringConvertible {
    case filtering = "filtering"
    case tagging = "tagging"
    case commitment = "commitment"
    case followup = "followup"
    case context = "context"
    case reminder = "reminder"
    
    var description: String {
        return self.rawValue
    }
}

struct AITask: Identifiable, Codable {
    let id: UUID
    var description: String
    let source: ContentSource
    var tags: [ContentTag]
    var priority: ProcessingPriority
    var status: TaskStatus
    var dueDate: Date?
    let createdDate: Date
    var modifiedDate: Date
    var relevanceScore: Float
    var userModified: Bool = false
    
    mutating func applyUpdates(_ updates: [String: Any]) {
        if let newDescription = updates["description"] as? String {
            description = newDescription
        }
        if let newDueDate = updates["dueDate"] as? Date {
            dueDate = newDueDate
        }
        if let newPriority = updates["priority"] as? ProcessingPriority {
            priority = newPriority
        }
        if let newStatus = updates["status"] as? TaskStatus {
            status = newStatus
        }
        modifiedDate = Date()
    }
}

enum TaskStatus: String, Codable {
    case pending = "pending"
    case in_progress = "in_progress"
    case completed = "completed"
    case snoozed = "snoozed"
    case dismissed = "dismissed"
}

enum TaskModification {
    case changeDueDate(Date)
    case changePriority(ProcessingPriority)
    case changeDescription(String)
    case markCompleted
    case markInProgress
}

// MARK: - Pipeline Statistics Data Structures

struct PipelineStatistics {
    let totalItemsProcessed: Int
    let itemsFiltered: Int
    let itemsPassed: Int
    let filterEfficiency: Double
    let vectorDatabaseSize: Int
    let activeTasks: Int
    let completedTasks: Int
    let urgentTasks: Int
    let overdueeTasks: Int
}

struct AgentStatus {
    let name: String
    let type: AIAgentType
    let isActive: Bool
    let lastActivity: Date
    let processedCount: Int
}

struct ProcessedItemResult {
    let id: UUID
    let originalContent: String
    let source: ContentSource
    let tags: [ContentTag]
    let aiSummary: String
    let confidence: Double
    let processingTime: TimeInterval
    let timestamp: Date
}