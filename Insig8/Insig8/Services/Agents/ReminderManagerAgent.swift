import Foundation
import UserNotifications
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Reminder Manager Agent

@MainActor  
class ReminderManagerAgent: BaseAIAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "ReminderManager")
    
    // Reminder Storage
    private var activeReminders: [UUID: SmartReminder] = [:]
    private var snoozedReminders: [UUID: SmartReminder] = [:]
    private let reminderStore = ReminderPersistenceStore()
    
    // Scheduling
    private let notificationCenter = UNUserNotificationCenter.current()
    private var reminderTimer: Timer?
    
    // Intelligence
    private let reminderIntelligence = ReminderIntelligenceEngine()
    
    init(communicationBus: AgentCommunicationBus? = nil) {
        super.init(
            specialization: .reminderManager,
            memorySize: 300,
            communicationBus: communicationBus
        )
        
        setupReminderScheduling()
        loadPersistedReminders()
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        isProcessing = true
        defer { isProcessing = false }
        
        logger.info("Processing reminder task: \(task.description)")
        
        switch task.type {
        case .reminder:
            return try await processReminderRequest(task)
        case .monitoring:
            return try await monitorReminders(task)
        default:
            throw AgentError.invalidTask
        }
    }
    
    override func receiveMessage(_ message: AgentMessage) async {
        await super.receiveMessage(message)
        
        switch message.type {
        case .commitmentDetected:
            await handleCommitmentMessage(message)
        case .actionRequired:
            await handleActionRequiredMessage(message)
        case .urgentNotification:
            await handleUrgentMessage(message)
        default:
            break
        }
    }
    
    // MARK: - Reminder Processing
    
    private func processReminderRequest(_ task: AgentTask) async throws -> AgentResponse {
        guard let reminderType = task.parameters["type"] as? String else {
            return try await createReminderFromTask(task)
        }
        
        switch reminderType {
        case "create":
            return try await createReminder(task)
        case "modify":
            return try await modifyReminder(task)
        case "snooze":
            return try await snoozeReminder(task)
        case "dismiss":
            return try await dismissReminder(task)
        case "check_fulfillment":
            return try await checkReminderFulfillment(task)
        default:
            throw AgentError.invalidTask
        }
    }
    
    private func createReminderFromTask(_ task: AgentTask) async throws -> AgentResponse {
        // Extract reminder information from task
        let description = task.parameters["description"] as? String ?? task.description
        let dueDate = task.parameters["dueDate"] as? Date ?? task.deadline
        let participants = task.parameters["participants"] as? [String] ?? []
        let commitmentId = task.parameters["commitmentId"] as? UUID
        
        // Create smart reminder
        let reminder = SmartReminder(
            id: UUID(),
            description: description,
            type: .followUp,
            priority: task.priority,
            scheduledDate: dueDate ?? suggestReminderTime(for: task.priority),
            createdDate: Date(),
            participants: participants,
            commitmentId: commitmentId,
            status: .active,
            metadata: extractMetadata(from: task.parameters)
        )
        
        // Add intelligence analysis
        let intelligence = await reminderIntelligence.analyzeReminder(reminder, context: task.parameters)
        var enhancedReminder = reminder
        enhancedReminder.intelligenceData = intelligence
        
        // Schedule the reminder
        try await scheduleReminder(enhancedReminder)
        activeReminders[enhancedReminder.id] = enhancedReminder
        
        // Persist
        await reminderStore.saveReminder(enhancedReminder)
        
        // Store in memory
        memory.store(MemoryItem(
            content: "Created reminder: \(description)",
            source: .manual,
            tags: [.reminder, .task],
            timestamp: Date(),
            importance: Double(task.priority.rawValue) / 4.0
        ))
        
        logger.info("Created reminder: \(enhancedReminder.id)")
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "reminderId": enhancedReminder.id,
                "scheduledDate": enhancedReminder.scheduledDate as Any,
                "intelligence": intelligence
            ],
            confidence: 0.9,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func createReminder(_ task: AgentTask) async throws -> AgentResponse {
        return try await createReminderFromTask(task)
    }
    
    private func modifyReminder(_ task: AgentTask) async throws -> AgentResponse {
        guard let reminderId = task.parameters["reminderId"] as? UUID,
              var reminder = activeReminders[reminderId] else {
            throw AgentError.processingFailed("Reminder not found")
        }
        
        // Apply modifications
        if let newDate = task.parameters["newDate"] as? Date {
            reminder.scheduledDate = newDate
        }
        
        if let newDescription = task.parameters["newDescription"] as? String {
            reminder.description = newDescription
        }
        
        if let newPriority = task.parameters["newPriority"] as? ProcessingPriority {
            reminder.priority = newPriority
        }
        
        reminder.modifiedDate = Date()
        reminder.userModified = true
        
        // Re-schedule
        try await rescheduleReminder(reminder)
        activeReminders[reminderId] = reminder
        
        // Update persistence
        await reminderStore.updateReminder(reminder)
        
        logger.info("Modified reminder: \(reminderId)")
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["modifiedReminder": reminder],
            confidence: 1.0,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func snoozeReminder(_ task: AgentTask) async throws -> AgentResponse {
        guard let reminderId = task.parameters["reminderId"] as? UUID,
              var reminder = activeReminders[reminderId] else {
            throw AgentError.processingFailed("Reminder not found")
        }
        
        let snoozeInterval = task.parameters["snoozeInterval"] as? TimeInterval ?? 3600 // 1 hour default
        
        reminder.scheduledDate = Date().addingTimeInterval(snoozeInterval)
        reminder.status = .snoozed
        reminder.snoozeCount += 1
        
        // Move to snoozed reminders
        activeReminders.removeValue(forKey: reminderId)
        snoozedReminders[reminderId] = reminder
        
        // Re-schedule
        try await scheduleReminder(reminder)
        
        // Update persistence
        await reminderStore.updateReminder(reminder)
        
        logger.info("Snoozed reminder: \(reminderId) for \(snoozeInterval) seconds")
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["snoozedUntil": reminder.scheduledDate],
            confidence: 1.0,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func dismissReminder(_ task: AgentTask) async throws -> AgentResponse {
        guard let reminderId = task.parameters["reminderId"] as? UUID else {
            throw AgentError.processingFailed("Reminder ID not provided")
        }
        
        // Remove from active reminders
        if var reminder = activeReminders.removeValue(forKey: reminderId) {
            reminder.status = .dismissed
            await reminderStore.updateReminder(reminder)
        } else if var reminder = snoozedReminders.removeValue(forKey: reminderId) {
            reminder.status = .dismissed
            await reminderStore.updateReminder(reminder)
        }
        
        // Cancel notification
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderId.uuidString])
        
        logger.info("Dismissed reminder: \(reminderId)")
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["dismissed": true],
            confidence: 1.0,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func checkReminderFulfillment(_ task: AgentTask) async throws -> AgentResponse {
        guard let reminderId = task.parameters["reminderId"] as? UUID,
              let reminder = activeReminders[reminderId] ?? snoozedReminders[reminderId] else {
            throw AgentError.processingFailed("Reminder not found")
        }
        
        // Check if the commitment has been fulfilled
        let fulfillmentStatus = await checkCommitmentFulfillment(reminder)
        
        var updatedReminder = reminder
        updatedReminder.fulfillmentStatus = fulfillmentStatus
        
        if fulfillmentStatus == .fulfilled {
            updatedReminder.status = .completed
            activeReminders.removeValue(forKey: reminderId)
            snoozedReminders.removeValue(forKey: reminderId)
            
            // Cancel notification
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderId.uuidString])
        }
        
        await reminderStore.updateReminder(updatedReminder)
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "fulfillmentStatus": fulfillmentStatus.rawValue,
                "reminder": updatedReminder
            ],
            confidence: 0.8,
            suggestedActions: generateFulfillmentActions(fulfillmentStatus, reminder: updatedReminder),
            error: nil
        )
    }
    
    // MARK: - Message Handlers
    
    private func handleCommitmentMessage(_ message: AgentMessage) async {
        guard case .commitment(let commitmentInfo) = message.content else { return }
        
        logger.info("Creating reminder for commitment: \(commitmentInfo.commitmentId)")
        
        // Create reminder for the commitment
        let reminderTime = commitmentInfo.deadline ?? suggestReminderTime(for: .high)
        
        let reminder = SmartReminder(
            id: UUID(),
            description: "Follow up on: \(commitmentInfo.description)",
            type: .commitmentFollowUp,
            priority: .high,
            scheduledDate: reminderTime,
            createdDate: Date(),
            participants: commitmentInfo.participants,
            commitmentId: commitmentInfo.commitmentId,
            status: .active
        )
        
        do {
            try await scheduleReminder(reminder)
            activeReminders[reminder.id] = reminder
            await reminderStore.saveReminder(reminder)
        } catch {
            logger.error("Failed to create commitment reminder: \(error)")
        }
    }
    
    private func handleActionRequiredMessage(_ message: AgentMessage) async {
        guard case .action(let actionInfo) = message.content else { return }
        
        let reminder = SmartReminder(
            id: UUID(),
            description: actionInfo.description,
            type: .actionItem,
            priority: actionInfo.urgency,
            scheduledDate: actionInfo.dueDate ?? suggestReminderTime(for: actionInfo.urgency),
            createdDate: Date(),
            participants: [],
            commitmentId: actionInfo.relatedCommitmentId,
            status: .active
        )
        
        do {
            try await scheduleReminder(reminder)
            activeReminders[reminder.id] = reminder
            await reminderStore.saveReminder(reminder)
        } catch {
            logger.error("Failed to create action reminder: \(error)")
        }
    }
    
    private func handleUrgentMessage(_ message: AgentMessage) async {
        // Create immediate reminder for urgent items
        let reminder = SmartReminder(
            id: UUID(),
            description: "URGENT: \(message.content)",
            type: .urgent,
            priority: .urgent,
            scheduledDate: Date().addingTimeInterval(300), // 5 minutes
            createdDate: Date(),
            participants: [],
            commitmentId: nil,
            status: .active
        )
        
        do {
            try await scheduleReminder(reminder)
            activeReminders[reminder.id] = reminder
            await reminderStore.saveReminder(reminder)
        } catch {
            logger.error("Failed to create urgent reminder: \(error)")
        }
    }
    
    // MARK: - Scheduling
    
    private func setupReminderScheduling() {
        // Set up periodic check for reminders
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkDueReminders()
            }
        }
    }
    
    private func scheduleReminder(_ reminder: SmartReminder) async throws {
        // Schedule system notification
        let content = UNMutableNotificationContent()
        content.title = getReminderTitle(for: reminder.type)
        content.body = reminder.description
        content.sound = getReminderSound(for: reminder.priority)
        content.userInfo = [
            "reminderId": reminder.id.uuidString,
            "type": reminder.type.rawValue
        ]
        
        // Create trigger
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.scheduledDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled notification for reminder: \(reminder.id)")
    }
    
    private func rescheduleReminder(_ reminder: SmartReminder) async throws {
        // Cancel existing notification
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
        
        // Schedule new notification
        try await scheduleReminder(reminder)
    }
    
    private func checkDueReminders() async {
        let now = Date()
        let dueReminders = activeReminders.values.filter { $0.scheduledDate <= now }
        
        for reminder in dueReminders {
            await processDueReminder(reminder)
        }
        
        // Check snoozed reminders
        let unsnoozedReminders = snoozedReminders.values.filter { $0.scheduledDate <= now }
        for reminder in unsnoozedReminders {
            snoozedReminders.removeValue(forKey: reminder.id)
            activeReminders[reminder.id] = reminder
            await processDueReminder(reminder)
        }
    }
    
    private func processDueReminder(_ reminder: SmartReminder) async {
        logger.info("Processing due reminder: \(reminder.id)")
        
        // Check if commitment is still relevant
        if reminder.commitmentId != nil {
            let fulfillmentStatus = await checkCommitmentFulfillment(reminder)
            
            if fulfillmentStatus == .fulfilled {
                // Automatically complete the reminder
                var completedReminder = reminder
                completedReminder.status = .completed
                completedReminder.fulfillmentStatus = .fulfilled
                
                activeReminders.removeValue(forKey: reminder.id)
                await reminderStore.updateReminder(completedReminder)
                
                logger.info("Auto-completed fulfilled reminder: \(reminder.id)")
                return
            }
        }
        
        // Send notification to communication bus
        if let bus = communicationBus {
            let message = AgentMessage(
                type: .reminderScheduled,
                from: specialization,
                content: .text("Reminder due: \(reminder.description)"),
                priority: reminder.priority == .urgent ? .urgent : .normal
            )
            
            await bus.broadcast(message)
        }
    }
    
    // MARK: - Commitment Fulfillment
    
    private func checkCommitmentFulfillment(_ reminder: SmartReminder) async -> FulfillmentStatus {
        guard reminder.commitmentId != nil else {
            return .unknown
        }
        
        // Search for evidence of fulfillment in recent communications
        let searchQuery = reminder.description + " " + reminder.participants.joined(separator: " ")
        let recentMemories = await memory.recall(matching: searchQuery, limit: 10)
        
        // Look for fulfillment indicators
        let fulfillmentKeywords = ["done", "completed", "sent", "delivered", "finished", "resolved"]
        
        for memoryItem in recentMemories {
            let content = memoryItem.content.lowercased()
            for keyword in fulfillmentKeywords {
                if content.contains(keyword) && 
                   memoryItem.timestamp > reminder.createdDate {
                    return .fulfilled
                }
            }
        }
        
        // Check with communication analyzer for more sophisticated analysis
        if let bus = communicationBus {
            let analysisMessage = AgentMessage(
                type: .searchRequest,
                from: specialization,
                to: .communicationAnalyzer,
                content: .searchQuery(SearchQueryInfo(
                    query: searchQuery,
                    searchScope: .conversations,
                    timeRange: DateInterval(start: reminder.createdDate, end: Date()),
                    requiredTags: [.commitment]
                )),
                priority: .normal
            )
            
            await bus.sendMessage(analysisMessage, to: .communicationAnalyzer)
        }
        
        // Default to not fulfilled
        return .notFulfilled
    }
    
    // MARK: - Reminder Intelligence
    
    private func suggestReminderTime(for priority: ProcessingPriority) -> Date {
        let now = Date()
        
        switch priority {
        case .urgent:
            return now.addingTimeInterval(300) // 5 minutes
        case .high:
            return now.addingTimeInterval(3600) // 1 hour
        case .medium:
            return now.addingTimeInterval(10800) // 3 hours
        case .low:
            return now.addingTimeInterval(86400) // 24 hours
        }
    }
    
    private func getReminderTitle(for type: ReminderType) -> String {
        switch type {
        case .followUp:
            return "Follow-up Required"
        case .commitmentFollowUp:
            return "Commitment Follow-up"
        case .actionItem:
            return "Action Item"
        case .urgent:
            return "🚨 Urgent Reminder"
        case .meeting:
            return "Meeting Reminder"
        case .deadline:
            return "Deadline Approaching"
        }
    }
    
    private func getReminderSound(for priority: ProcessingPriority) -> UNNotificationSound {
        switch priority {
        case .urgent:
            return .criticalSoundNamed(UNNotificationSoundName("urgent.caf"))
        case .high:
            return .defaultCritical
        default:
            return .default
        }
    }
    
    private func extractMetadata(from parameters: [String: Any]) -> [String: Any] {
        var metadata: [String: Any] = [:]
        
        if let source = parameters["source"] {
            metadata["source"] = source
        }
        
        if let platform = parameters["platform"] {
            metadata["platform"] = platform
        }
        
        if let contextId = parameters["contextId"] {
            metadata["contextId"] = contextId
        }
        
        return metadata
    }
    
    private func generateFulfillmentActions(_ status: FulfillmentStatus, reminder: SmartReminder) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []
        
        switch status {
        case .notFulfilled:
            actions.append(SuggestedAction(
                description: "Create escalation reminder",
                targetAgent: .reminderManager,
                priority: .high,
                parameters: ["originalReminder": reminder.id]
            ))
            
        case .partiallyFulfilled:
            actions.append(SuggestedAction(
                description: "Create follow-up for partial completion",
                targetAgent: .followupTracking,
                priority: .medium,
                parameters: ["reminder": reminder.id]
            ))
            
        case .fulfilled:
            // No additional actions needed
            break
            
        case .unknown:
            actions.append(SuggestedAction(
                description: "Request manual verification",
                targetAgent: .communicationAnalyzer,
                priority: .low,
                parameters: ["reminder": reminder.id]
            ))
        }
        
        return actions
    }
    
    // MARK: - Monitoring
    
    private func monitorReminders(_ task: AgentTask) async throws -> AgentResponse {
        // Get reminder statistics
        let activeCount = activeReminders.count
        let snoozedCount = snoozedReminders.count
        let overdueCount = activeReminders.values.filter { $0.scheduledDate < Date() }.count
        
        // Analyze reminder patterns
        let patterns = analyzeReminderPatterns()
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "activeReminders": activeCount,
                "snoozedReminders": snoozedCount,
                "overdueReminders": overdueCount,
                "patterns": patterns
            ],
            confidence: 1.0,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func analyzeReminderPatterns() -> [String: Any] {
        let allReminders = Array(activeReminders.values) + Array(snoozedReminders.values)
        
        let typeDistribution = Dictionary(grouping: allReminders, by: { $0.type })
            .mapValues { $0.count }
        
        let priorityDistribution = Dictionary(grouping: allReminders, by: { $0.priority })
            .mapValues { $0.count }
        
        return [
            "typeDistribution": typeDistribution,
            "priorityDistribution": priorityDistribution,
            "averageSnoozeCount": allReminders.map { $0.snoozeCount }.reduce(0, +) / max(allReminders.count, 1)
        ]
    }
    
    // MARK: - Persistence
    
    private func loadPersistedReminders() {
        Task {
            let reminders = await reminderStore.loadAllReminders()
            
            for reminder in reminders {
                switch reminder.status {
                case .active:
                    activeReminders[reminder.id] = reminder
                case .snoozed:
                    snoozedReminders[reminder.id] = reminder
                default:
                    break
                }
            }
            
            logger.info("Loaded \(reminders.count) persisted reminders")
        }
    }
    
    // MARK: - Public Interface
    
    func getActiveReminders() -> [SmartReminder] {
        return Array(activeReminders.values)
    }
    
    func getSnoozedReminders() -> [SmartReminder] {
        return Array(snoozedReminders.values)
    }
    
    func getUserModifiableReminders() -> [SmartReminder] {
        return (Array(activeReminders.values) + Array(snoozedReminders.values))
            .filter { $0.status != .completed && $0.status != .dismissed }
    }
}

// MARK: - Data Models

struct SmartReminder: Identifiable, Codable {
    let id: UUID
    var description: String
    let type: ReminderType
    var priority: ProcessingPriority
    var scheduledDate: Date
    let createdDate: Date
    var modifiedDate: Date?
    var participants: [String]
    let commitmentId: UUID?
    var status: ReminderStatus
    var snoozeCount: Int = 0
    var userModified: Bool = false
    var fulfillmentStatus: FulfillmentStatus = .unknown
    var intelligenceData: ReminderIntelligence?
    var metadata: [String: Any] = [:]
    
    enum CodingKeys: String, CodingKey {
        case id, description, type, priority, scheduledDate, createdDate
        case modifiedDate, participants, commitmentId, status, snoozeCount
        case userModified, fulfillmentStatus, intelligenceData
    }
}

enum ReminderType: String, Codable {
    case followUp = "follow_up"
    case commitmentFollowUp = "commitment_follow_up"
    case actionItem = "action_item"
    case urgent = "urgent"
    case meeting = "meeting"
    case deadline = "deadline"
}

enum ReminderStatus: String, Codable {
    case active = "active"
    case snoozed = "snoozed"
    case completed = "completed"
    case dismissed = "dismissed"
}

enum FulfillmentStatus: String, Codable {
    case fulfilled = "fulfilled"
    case partiallyFulfilled = "partially_fulfilled"
    case notFulfilled = "not_fulfilled"
    case unknown = "unknown"
}

struct ReminderIntelligence: Codable {
    let suggestedTime: Date
    let confidenceScore: Double
    let contextFactors: [String]
    let userPatterns: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case suggestedTime, confidenceScore, contextFactors, userPatterns
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        suggestedTime = try container.decode(Date.self, forKey: .suggestedTime)
        confidenceScore = try container.decode(Double.self, forKey: .confidenceScore)
        contextFactors = try container.decode([String].self, forKey: .contextFactors)
        
        // Decode userPatterns as JSON data
        if let patternsData = try? container.decode(Data.self, forKey: .userPatterns),
           let patternsDict = try? JSONSerialization.jsonObject(with: patternsData) as? [String: Any] {
            userPatterns = patternsDict
        } else {
            userPatterns = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(suggestedTime, forKey: .suggestedTime)
        try container.encode(confidenceScore, forKey: .confidenceScore)
        try container.encode(contextFactors, forKey: .contextFactors)
        
        // Encode userPatterns as JSON data
        if let patternsData = try? JSONSerialization.data(withJSONObject: userPatterns) {
            try container.encode(patternsData, forKey: .userPatterns)
        }
    }
    
    init(suggestedTime: Date, confidenceScore: Double, contextFactors: [String], userPatterns: [String: Any]) {
        self.suggestedTime = suggestedTime
        self.confidenceScore = confidenceScore
        self.contextFactors = contextFactors
        self.userPatterns = userPatterns
    }
}

// MARK: - Intelligence Engine

class ReminderIntelligenceEngine {
    
    func analyzeReminder(_ reminder: SmartReminder, context: [String: Any]) async -> ReminderIntelligence {
        // Analyze optimal timing based on context
        let suggestedTime = calculateOptimalTime(reminder, context: context)
        
        // Calculate confidence
        let confidence = calculateConfidence(reminder, context: context)
        
        // Extract context factors
        let contextFactors = extractContextFactors(context)
        
        return ReminderIntelligence(
            suggestedTime: suggestedTime,
            confidenceScore: confidence,
            contextFactors: contextFactors,
            userPatterns: [:]
        )
    }
    
    private func calculateOptimalTime(_ reminder: SmartReminder, context: [String: Any]) -> Date {
        // Simple time calculation - in practice this would be more sophisticated
        let baseTime = reminder.scheduledDate
        
        // Adjust based on priority
        switch reminder.priority {
        case .urgent:
            return baseTime
        case .high:
            return baseTime.addingTimeInterval(-1800) // 30 minutes earlier
        case .medium:
            return baseTime
        case .low:
            return baseTime.addingTimeInterval(3600) // 1 hour later
        }
    }
    
    private func calculateConfidence(_ reminder: SmartReminder, context: [String: Any]) -> Double {
        var confidence = 0.5
        
        if reminder.commitmentId != nil {
            confidence += 0.3
        }
        
        if !reminder.participants.isEmpty {
            confidence += 0.2
        }
        
        return min(confidence, 1.0)
    }
    
    private func extractContextFactors(_ context: [String: Any]) -> [String] {
        var factors: [String] = []
        
        if context["platform"] != nil {
            factors.append("platform_context")
        }
        
        if context["participants"] != nil {
            factors.append("participant_context")
        }
        
        if context["urgency"] != nil {
            factors.append("urgency_context")
        }
        
        return factors
    }
}

// MARK: - Persistence Store

class ReminderPersistenceStore {
    private let userDefaults = UserDefaults.standard
    private let remindersKey = "smart_reminders"
    
    func saveReminder(_ reminder: SmartReminder) async {
        var reminders = await loadAllReminders()
        
        // Remove existing reminder with same ID
        reminders.removeAll { $0.id == reminder.id }
        
        // Add updated reminder
        reminders.append(reminder)
        
        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(reminders) {
            userDefaults.set(data, forKey: remindersKey)
        }
    }
    
    func updateReminder(_ reminder: SmartReminder) async {
        await saveReminder(reminder)
    }
    
    func loadAllReminders() async -> [SmartReminder] {
        guard let data = userDefaults.data(forKey: remindersKey),
              let reminders = try? JSONDecoder().decode([SmartReminder].self, from: data) else {
            return []
        }
        
        return reminders
    }
    
    func deleteReminder(_ reminderId: UUID) async {
        var reminders = await loadAllReminders()
        reminders.removeAll { $0.id == reminderId }
        
        if let data = try? JSONEncoder().encode(reminders) {
            userDefaults.set(data, forKey: remindersKey)
        }
    }
}