import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Context Tracker Agent

@MainActor
class ContextTrackerAgent: BaseAIAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "ContextTracker")
    
    // Context Management
    private var conversationThreads: [UUID: ConversationThread] = [:]
    private var activeContexts: [UUID: ContextInfo] = [:]
    private let maxThreadAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    init(communicationBus: AgentCommunicationBus? = nil) {
        super.init(
            specialization: .contextTracker,
            memorySize: 500, // Larger memory for context tracking
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        isProcessing = true
        defer { isProcessing = false }
        
        logger.info("Tracking context for task: \(task.description)")
        
        switch task.type {
        case .analysis:
            return try await analyzeContext(task)
        case .monitoring:
            return try await monitorContextChanges(task)
        case .search:
            return try await searchContext(task)
        default:
            throw AgentError.invalidTask
        }
    }
    
    // MARK: - Context Analysis
    
    private func analyzeContext(_ task: AgentTask) async throws -> AgentResponse {
        guard let content = task.parameters["content"] as? String,
              let source = task.parameters["source"] as? ContentSource else {
            throw AgentError.invalidTask
        }
        
        // Extract context information
        let contextInfo = await extractContextInfo(from: content, source: source)
        
        // Find or create conversation thread
        let thread = findOrCreateThread(for: contextInfo)
        
        // Update thread with new message
        updateThread(thread, with: content, context: contextInfo)
        
        // Analyze thread for patterns
        let threadAnalysis = await analyzeThread(thread)
        
        // Store in memory
        storeContextInMemory(contextInfo, thread: thread)
        
        // Notify other agents about context update
        await notifyContextUpdate(contextInfo, thread: thread)
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "contextId": contextInfo.contextId,
                "threadId": thread.id,
                "participants": contextInfo.participants,
                "platform": contextInfo.platform,
                "threadAnalysis": threadAnalysis
            ],
            confidence: 0.8,
            suggestedActions: generateContextActions(thread, analysis: threadAnalysis),
            error: nil
        )
    }
    
    private func extractContextInfo(from content: String, source: ContentSource) async -> ContextInfo {
        var participants: [String] = []
        var platform = "unknown"
        var relatedContent: [UUID] = []
        
        // Extract platform and participants based on source
        switch source {
        case .email(let sender, _):
            platform = "email"
            if let sender = sender {
                participants.append(sender)
            }
            // Extract recipients from content
            participants.append(contentsOf: extractEmailParticipants(from: content))
            
        case .screenCapture(let appName):
            platform = appName.lowercased()
            participants = extractParticipantsFromScreenCapture(content, app: appName)
            
        case .meeting(let meetingParticipants):
            platform = "meeting"
            participants = meetingParticipants
            
        default:
            platform = "general"
        }
        
        // Find related content in memory
        let memories = await memory.recall(matching: content, limit: 5)
        relatedContent = memories.map { _ in UUID() } // Simplified for now
        
        let contextInfo = ContextInfo(
            contextId: UUID(),
            conversationThread: extractThreadIdentifier(from: content, source: source),
            participants: Array(Set(participants)), // Remove duplicates
            platform: platform,
            relatedContent: relatedContent
        )
        
        activeContexts[contextInfo.contextId] = contextInfo
        
        return contextInfo
    }
    
    private func extractThreadIdentifier(from content: String, source: ContentSource) -> String? {
        switch source {
        case .email(_, let subject):
            return subject
            
        case .screenCapture(let appName):
            // Extract channel or conversation ID based on app
            if appName.lowercased().contains("slack") {
                return extractSlackChannel(from: content)
            } else if appName.lowercased().contains("teams") {
                return extractTeamsChannel(from: content)
            }
            
        default:
            break
        }
        
        return nil
    }
    
    private func extractSlackChannel(from content: String) -> String? {
        // Look for Slack channel patterns
        let channelPattern = "#[a-z0-9-_]+"
        if let regex = try? NSRegularExpression(pattern: channelPattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            if let match = matches.first,
               let range = Range(match.range, in: content) {
                return String(content[range])
            }
        }
        
        return nil
    }
    
    private func extractTeamsChannel(from content: String) -> String? {
        // Look for Teams channel indicators
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("General") || line.contains("Team") || line.contains("Channel") {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    private func extractEmailParticipants(from content: String) -> [String] {
        var participants: [String] = []
        
        // Extract from To:, CC:, etc.
        let patterns = ["To:", "Cc:", "From:"]
        for pattern in patterns {
            if let range = content.range(of: pattern) {
                let afterPattern = content[range.upperBound...]
                if let endRange = afterPattern.firstIndex(of: "\n") {
                    let emails = String(afterPattern[..<endRange])
                        .split(separator: ",")
                        .compactMap { email in
                            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            // Extract email address if in "Name <email>" format
                            if let startIndex = trimmed.firstIndex(of: "<"),
                               let endIndex = trimmed.firstIndex(of: ">") {
                                return String(trimmed[trimmed.index(after: startIndex)..<endIndex])
                            }
                            return trimmed.contains("@") ? String(trimmed) : nil
                        }
                    participants.append(contentsOf: emails)
                }
            }
        }
        
        return participants
    }
    
    private func extractParticipantsFromScreenCapture(_ content: String, app: String) -> [String] {
        var participants: [String] = []
        
        // Look for @mentions
        let mentionPattern = "@[a-zA-Z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: mentionPattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    let mention = String(content[range]).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    participants.append(mention)
                }
            }
        }
        
        // App-specific participant extraction
        if app.lowercased().contains("slack") || app.lowercased().contains("teams") {
            // Look for message authors (usually before timestamps)
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("AM") || line.contains("PM") || line.contains(":") {
                    // Extract name before timestamp
                    let components = line.components(separatedBy: " ")
                    if components.count > 1 {
                        let possibleName = components[0]
                        if !possibleName.isEmpty && !possibleName.contains(":") {
                            participants.append(possibleName)
                        }
                    }
                }
            }
        }
        
        return Array(Set(participants))
    }
    
    // MARK: - Thread Management
    
    private func findOrCreateThread(for context: ContextInfo) -> ConversationThread {
        // Try to find existing thread
        if let threadId = context.conversationThread {
            for (_, thread) in conversationThreads {
                if thread.identifier == threadId &&
                   thread.platform == context.platform &&
                   Set(thread.participants).intersection(Set(context.participants)).count > 0 {
                    return thread
                }
            }
        }
        
        // Create new thread
        let thread = ConversationThread(
            id: UUID(),
            identifier: context.conversationThread,
            participants: context.participants,
            platform: context.platform,
            messages: [],
            commitments: [],
            createdAt: Date(),
            lastUpdated: Date()
        )
        
        conversationThreads[thread.id] = thread
        return thread
    }
    
    private func updateThread(_ thread: ConversationThread, with content: String, context: ContextInfo) {
        var updatedThread = thread
        
        // Add new message
        let message = ThreadMessage(
            id: UUID(),
            content: content,
            sender: context.participants.first,
            timestamp: Date(),
            contextId: context.contextId
        )
        updatedThread.messages.append(message)
        
        // Update participants
        let allParticipants = Set(updatedThread.participants).union(Set(context.participants))
        updatedThread.participants = Array(allParticipants)
        
        // Update timestamp
        updatedThread.lastUpdated = Date()
        
        conversationThreads[thread.id] = updatedThread
    }
    
    private func analyzeThread(_ thread: ConversationThread) async -> ThreadAnalysis {
        // Analyze conversation flow
        let messageCount = thread.messages.count
        let participantCount = thread.participants.count
        
        // Calculate response times
        var responseTimes: [TimeInterval] = []
        for i in 1..<thread.messages.count {
            let timeDiff = thread.messages[i].timestamp.timeIntervalSince(thread.messages[i-1].timestamp)
            responseTimes.append(timeDiff)
        }
        
        let avgResponseTime = responseTimes.isEmpty ? 0 : responseTimes.reduce(0, +) / Double(responseTimes.count)
        
        // Check for unresponded messages
        let lastMessage = thread.messages.last
        let hasUnrespondedMessage = lastMessage != nil && 
            Date().timeIntervalSince(lastMessage!.timestamp) > 3600 && // More than 1 hour
            thread.messages.count == 1 // Only one message in thread
        
        // Analyze topic continuity
        let topicContinuity = analyzeTopicContinuity(thread.messages)
        
        return ThreadAnalysis(
            threadId: thread.id,
            messageCount: messageCount,
            participantCount: participantCount,
            averageResponseTime: avgResponseTime,
            lastActivity: thread.lastUpdated,
            hasUnrespondedMessages: hasUnrespondedMessage,
            topicContinuity: topicContinuity,
            sentiment: analyzeSentiment(thread.messages)
        )
    }
    
    private func analyzeTopicContinuity(_ messages: [ThreadMessage]) -> Double {
        guard messages.count > 1 else { return 1.0 }
        
        // Simple topic continuity based on common words
        var continuityScore = 0.0
        
        for i in 1..<messages.count {
            let prevWords = Set(messages[i-1].content.lowercased().split(separator: " ").map { String($0) })
            let currWords = Set(messages[i].content.lowercased().split(separator: " ").map { String($0) })
            
            let commonWords = prevWords.intersection(currWords)
            let totalWords = prevWords.union(currWords)
            
            if !totalWords.isEmpty {
                continuityScore += Double(commonWords.count) / Double(totalWords.count)
            }
        }
        
        return continuityScore / Double(messages.count - 1)
    }
    
    private func analyzeSentiment(_ messages: [ThreadMessage]) -> String {
        // Aggregate sentiment across messages
        var positiveCount = 0
        var negativeCount = 0
        
        let positiveWords = ["thanks", "great", "good", "excellent", "happy", "appreciate"]
        let negativeWords = ["problem", "issue", "concern", "sorry", "frustrated", "confused"]
        
        for message in messages {
            let lowercased = message.content.lowercased()
            
            for word in positiveWords {
                if lowercased.contains(word) {
                    positiveCount += 1
                }
            }
            
            for word in negativeWords {
                if lowercased.contains(word) {
                    negativeCount += 1
                }
            }
        }
        
        if positiveCount > negativeCount {
            return "positive"
        } else if negativeCount > positiveCount {
            return "negative"
        } else {
            return "neutral"
        }
    }
    
    // MARK: - Context Monitoring
    
    private func monitorContextChanges(_ task: AgentTask) async throws -> AgentResponse {
        // Monitor for context changes and patterns
        let recentContexts = Array(activeContexts.values.suffix(10))
        
        // Analyze patterns
        let patterns = analyzeContextPatterns(recentContexts)
        
        // Clean up old threads
        cleanupOldThreads()
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "activeContexts": activeContexts.count,
                "conversationThreads": conversationThreads.count,
                "patterns": patterns
            ],
            confidence: 0.9,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func analyzeContextPatterns(_ contexts: [ContextInfo]) -> [String: Any] {
        var patterns: [String: Any] = [:]
        
        // Platform distribution
        let platformCounts = Dictionary(grouping: contexts, by: { $0.platform })
            .mapValues { $0.count }
        patterns["platformDistribution"] = platformCounts
        
        // Participant frequency
        let allParticipants = contexts.flatMap { $0.participants }
        let participantFrequency = Dictionary(grouping: allParticipants, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
        patterns["topParticipants"] = Array(participantFrequency)
        
        return patterns
    }
    
    private func cleanupOldThreads() {
        let cutoffDate = Date().addingTimeInterval(-maxThreadAge)
        
        conversationThreads = self.conversationThreads.filter { _, thread in
            thread.lastUpdated > cutoffDate
        }
        
        logger.info("Cleaned up old threads, remaining: \(self.conversationThreads.count)")
    }
    
    // MARK: - Context Search
    
    private func searchContext(_ task: AgentTask) async throws -> AgentResponse {
        guard let query = task.parameters["query"] as? String else {
            throw AgentError.invalidTask
        }
        
        var results: [ContextSearchResult] = []
        
        // Search in active contexts
        for (_, context) in activeContexts {
            if context.participants.contains(where: { $0.localizedCaseInsensitiveContains(query) }) ||
               context.platform.localizedCaseInsensitiveContains(query) {
                results.append(ContextSearchResult(
                    contextId: context.contextId,
                    relevance: 0.8,
                    context: context,
                    thread: nil
                ))
            }
        }
        
        // Search in conversation threads
        for (_, thread) in conversationThreads {
            let matchingMessages = thread.messages.filter { message in
                message.content.localizedCaseInsensitiveContains(query)
            }
            
            if !matchingMessages.isEmpty {
                results.append(ContextSearchResult(
                    contextId: thread.id,
                    relevance: Double(matchingMessages.count) / Double(thread.messages.count),
                    context: nil,
                    thread: thread
                ))
            }
        }
        
        // Sort by relevance
        results.sort { $0.relevance > $1.relevance }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["searchResults": results],
            confidence: 0.85,
            suggestedActions: [],
            error: nil
        )
    }
    
    // MARK: - Memory Management
    
    private func storeContextInMemory(_ context: ContextInfo, thread: ConversationThread) {
        let memoryItem = MemoryItem(
            content: "Thread: \(thread.identifier ?? "unknown") with \(context.participants.joined(separator: ", "))",
            source: .manual,
            tags: [.communication],
            timestamp: Date(),
            importance: 0.7
        )
        
        memory.store(memoryItem)
        memory.updateWorkingMemory(key: "currentThread", value: thread.id)
        memory.updateWorkingMemory(key: "currentContext", value: context.contextId)
    }
    
    // MARK: - Notifications
    
    private func notifyContextUpdate(_ context: ContextInfo, thread: ConversationThread) async {
        guard let bus = communicationBus else { return }
        
        let message = AgentMessage(
            type: .contextUpdate,
            from: specialization,
            content: .context(context),
            priority: .normal
        )
        
        await bus.broadcast(message)
    }
    
    // MARK: - Action Generation
    
    private func generateContextActions(_ thread: ConversationThread, analysis: ThreadAnalysis) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []
        
        // Suggest follow-up for unresponded messages
        if analysis.hasUnrespondedMessages {
            actions.append(SuggestedAction(
                description: "Create follow-up reminder for unresponded message",
                targetAgent: .reminderManager,
                priority: .high,
                parameters: [
                    "threadId": thread.id,
                    "participants": thread.participants
                ]
            ))
        }
        
        // Suggest commitment tracking for threads with commitments
        if !thread.commitments.isEmpty {
            actions.append(SuggestedAction(
                description: "Track commitments in conversation",
                targetAgent: .commitmentDetection,
                priority: .medium,
                parameters: [
                    "threadId": thread.id,
                    "commitments": thread.commitments
                ]
            ))
        }
        
        return actions
    }
}

// MARK: - Data Models

struct ConversationThread {
    let id: UUID
    let identifier: String? // Channel, subject line, etc.
    var participants: [String]
    let platform: String
    var messages: [ThreadMessage]
    var commitments: [UUID] // References to commitment IDs
    let createdAt: Date
    var lastUpdated: Date
}

struct ThreadMessage {
    let id: UUID
    let content: String
    let sender: String?
    let timestamp: Date
    let contextId: UUID
}

struct ThreadAnalysis {
    let threadId: UUID
    let messageCount: Int
    let participantCount: Int
    let averageResponseTime: TimeInterval
    let lastActivity: Date
    let hasUnrespondedMessages: Bool
    let topicContinuity: Double
    let sentiment: String
}

struct ContextSearchResult {
    let contextId: UUID
    let relevance: Double
    let context: ContextInfo?
    let thread: ConversationThread?
}