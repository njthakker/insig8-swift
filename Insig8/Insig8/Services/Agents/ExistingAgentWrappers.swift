import Foundation
import OSLog

// MARK: - Agent Wrappers for Existing Agents

/// Wrapper for ContentFilteringAgent to integrate with new communication system
@MainActor
class ContentFilteringAgentWrapper: BaseAIAgent {
    private let wrappedAgent = ContentFilteringAgent()
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .contentFiltering,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let item = task.parameters["item"] as? ProcessingItem else {
            throw AgentError.invalidTask
        }
        
        let shouldProcess = await wrappedAgent.shouldProcessContent(item)
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["shouldProcess": shouldProcess],
            confidence: 0.9,
            suggestedActions: [],
            error: nil
        )
    }
}

/// Wrapper for ContentTaggingAgent
@MainActor
class ContentTaggingAgentWrapper: BaseAIAgent {
    private let wrappedAgent = ContentTaggingAgent()
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .contentTagging,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let item = task.parameters["item"] as? ProcessingItem else {
            throw AgentError.invalidTask
        }
        
        let tags = await wrappedAgent.generateTags(for: item)
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["tags": tags],
            confidence: 0.8,
            suggestedActions: [],
            error: nil
        )
    }
}

/// Wrapper for CommitmentDetectionAgent
@MainActor
class CommitmentDetectionAgentWrapper: BaseAIAgent {
    private let wrappedAgent = CommitmentDetectionAgent()
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .commitmentDetection,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let item = task.parameters["item"] as? ProcessingItem,
              let tags = task.parameters["tags"] as? [ContentTag] else {
            throw AgentError.invalidTask
        }
        
        await wrappedAgent.processCommitment(item, tags: tags)
        
        // Notify about detected commitments
        if tags.contains(.commitment) {
            await notifyCommitmentDetected(item)
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["processed": true],
            confidence: 0.85,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func notifyCommitmentDetected(_ item: ProcessingItem) async {
        guard let bus = communicationBus else { return }
        
        let commitmentInfo = CommitmentInfo(
            commitmentId: UUID(),
            description: item.content,
            participants: extractParticipants(from: item.content),
            deadline: extractDeadline(from: item.content),
            source: item.source,
            confidence: 0.8
        )
        
        let message = AgentMessage(
            type: .commitmentDetected,
            from: specialization,
            content: .commitment(commitmentInfo),
            priority: item.priority == .urgent ? .urgent : .high
        )
        
        await bus.broadcast(message)
    }
    
    private func extractParticipants(from content: String) -> [String] {
        // Simple participant extraction - could be enhanced
        var participants: [String] = []
        
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
        
        return participants
    }
    
    private func extractDeadline(from content: String) -> Date? {
        // Simple deadline extraction
        let calendar = Calendar.current
        let now = Date()
        
        let lowercased = content.lowercased()
        
        if lowercased.contains("today") || lowercased.contains("eod") {
            return calendar.dateInterval(of: .day, for: now)?.end
        } else if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        } else if lowercased.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }
        
        return nil
    }
}

/// Wrapper for FollowupTrackingAgent
@MainActor
class FollowupTrackingAgentWrapper: BaseAIAgent {
    private let wrappedAgent = FollowupTrackingAgent()
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .followupTracking,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let item = task.parameters["item"] as? ProcessingItem,
              let tags = task.parameters["tags"] as? [ContentTag] else {
            throw AgentError.invalidTask
        }
        
        await wrappedAgent.trackFollowup(item, tags: tags)
        
        // Create action if followup is required
        if tags.contains(.followup_required) {
            await createFollowupAction(item)
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["tracked": true],
            confidence: 0.8,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func createFollowupAction(_ item: ProcessingItem) async {
        guard let bus = communicationBus else { return }
        
        let actionInfo = ActionInfo(
            actionId: UUID(),
            description: "Follow up on: \(item.content.prefix(100))",
            urgency: item.priority,
            dueDate: Date().addingTimeInterval(3600), // 1 hour
            relatedCommitmentId: nil
        )
        
        let message = AgentMessage(
            type: .actionRequired,
            from: specialization,
            content: .action(actionInfo),
            priority: item.priority == .urgent ? .urgent : .normal
        )
        
        await bus.broadcast(message)
    }
}

/// Wrapper for ContextCorrelationAgent
@MainActor
class ContextCorrelationAgentWrapper: BaseAIAgent {
    private let wrappedAgent = ContextCorrelationAgent()
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .contextCorrelation,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let item = task.parameters["item"] as? ProcessingItem,
              let tags = task.parameters["tags"] as? [ContentTag] else {
            throw AgentError.invalidTask
        }
        
        await wrappedAgent.correlateContext(item, tags: tags)
        
        // Send context update
        await sendContextUpdate(item, tags: tags)
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["correlated": true],
            confidence: 0.75,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func sendContextUpdate(_ item: ProcessingItem, tags: [ContentTag]) async {
        guard let bus = communicationBus else { return }
        
        let contextInfo = ContextInfo(
            contextId: UUID(),
            conversationThread: extractThreadIdentifier(from: item),
            participants: extractParticipants(from: item.content),
            platform: extractPlatform(from: item.source),
            relatedContent: []
        )
        
        let message = AgentMessage(
            type: .contextUpdate,
            from: specialization,
            content: .context(contextInfo),
            priority: .normal
        )
        
        await bus.broadcast(message)
    }
    
    private func extractThreadIdentifier(from item: ProcessingItem) -> String? {
        switch item.source {
        case .email(_, let subject):
            return subject
        case .screenCapture(let appName):
            return appName
        default:
            return nil
        }
    }
    
    private func extractParticipants(from content: String) -> [String] {
        // Reuse the same logic as in CommitmentDetectionAgentWrapper
        var participants: [String] = []
        
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
        
        return participants
    }
    
    private func extractPlatform(from source: ContentSource) -> String {
        switch source {
        case .email:
            return "email"
        case .screenCapture(let appName):
            return appName.lowercased()
        case .meeting:
            return "meeting"
        case .browser:
            return "browser"
        case .clipboard:
            return "clipboard"
        case .manual:
            return "manual"
        }
    }
}

/// Wrapper for SmartReminderAgent
@MainActor
class SmartReminderAgentWrapper: BaseAIAgent {
    private let wrappedAgent = SmartReminderAgent()
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .smartReminder,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let item = task.parameters["item"] as? ProcessingItem,
              let tags = task.parameters["tags"] as? [ContentTag] else {
            throw AgentError.invalidTask
        }
        
        if tags.contains(.urgent_action) {
            await wrappedAgent.createUrgentReminder(item, tags: tags)
            await notifyUrgentReminder(item)
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["reminder_created": tags.contains(.urgent_action)],
            confidence: 0.8,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func notifyUrgentReminder(_ item: ProcessingItem) async {
        guard let bus = communicationBus else { return }
        
        let message = AgentMessage(
            type: .reminderScheduled,
            from: specialization,
            content: .text("Urgent reminder created: \(item.content.prefix(100))"),
            priority: .urgent
        )
        
        await bus.broadcast(message)
    }
}

// MARK: - Additional Specialized Agents

/// Screen Analyzer Agent
@MainActor
class ScreenAnalyzerAgent: BaseAIAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "ScreenAnalyzer")
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .screenAnalyzer,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let content = task.parameters["content"] as? String,
              let appName = task.parameters["appName"] as? String else {
            throw AgentError.invalidTask
        }
        
        // Analyze screen content
        let analysis = await analyzeScreenContent(content, appName: appName)
        
        // Send results to other agents if commitments detected
        if !analysis.commitments.isEmpty {
            await notifyCommitmentsDetected(analysis.commitments, appName: appName)
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "commitments": analysis.commitments,
                "actionItems": analysis.actionItems,
                "participants": analysis.participants,
                "urgency": analysis.urgencyLevel.rawValue
            ],
            confidence: analysis.confidence,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func analyzeScreenContent(_ content: String, appName: String) async -> AgentScreenAnalysis {
        // App-specific parsing
        var commitments: [String] = []
        var actionItems: [String] = []
        var participants: [String] = []
        var urgencyLevel = ProcessingPriority.low
        
        // Extract participants based on app
        if appName.lowercased().contains("slack") || appName.lowercased().contains("teams") {
            participants = extractChatParticipants(content)
        } else if appName.lowercased().contains("mail") {
            participants = extractEmailParticipants(content)
        }
        
        // Look for commitments
        let commitmentKeywords = ["will do", "will send", "will get back", "will check", "will follow up"]
        for keyword in commitmentKeywords {
            if content.lowercased().contains(keyword) {
                // Extract the sentence containing the commitment
                let sentences = content.components(separatedBy: .newlines)
                for sentence in sentences {
                    if sentence.lowercased().contains(keyword) {
                        commitments.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
        
        // Look for action items
        let actionKeywords = ["need to", "should", "must", "have to", "action:", "todo:"]
        for keyword in actionKeywords {
            if content.lowercased().contains(keyword) {
                let sentences = content.components(separatedBy: .newlines)
                for sentence in sentences {
                    if sentence.lowercased().contains(keyword) {
                        actionItems.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
        
        // Analyze urgency
        let urgentKeywords = ["urgent", "asap", "critical", "important", "deadline"]
        for keyword in urgentKeywords {
            if content.lowercased().contains(keyword) {
                urgencyLevel = .high
                if keyword == "urgent" || keyword == "asap" {
                    urgencyLevel = .urgent
                }
                break
            }
        }
        
        let confidence = calculateScreenAnalysisConfidence(
            commitments: commitments,
            actionItems: actionItems,
            participants: participants
        )
        
        return AgentScreenAnalysis(
            commitments: commitments,
            actionItems: actionItems,
            participants: participants,
            urgencyLevel: urgencyLevel,
            confidence: confidence
        )
    }
    
    private func extractChatParticipants(_ content: String) -> [String] {
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
        
        // Look for message authors (usually before timestamps)
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("AM") || line.contains("PM") || line.contains(":") {
                let components = line.components(separatedBy: " ")
                if components.count > 1 {
                    let possibleName = components[0]
                    if !possibleName.isEmpty && !possibleName.contains(":") {
                        participants.append(possibleName)
                    }
                }
            }
        }
        
        return Array(Set(participants)) // Remove duplicates
    }
    
    private func extractEmailParticipants(_ content: String) -> [String] {
        var participants: [String] = []
        
        // Extract from To:, CC:, From: fields
        let patterns = ["To:", "Cc:", "From:"]
        for pattern in patterns {
            if let range = content.range(of: pattern) {
                let afterPattern = content[range.upperBound...]
                if let endRange = afterPattern.firstIndex(of: "\n") {
                    let emails = String(afterPattern[..<endRange])
                        .split(separator: ",")
                        .compactMap { email in
                            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    private func calculateScreenAnalysisConfidence(
        commitments: [String],
        actionItems: [String],
        participants: [String]
    ) -> Double {
        var confidence = 0.5
        
        if !commitments.isEmpty {
            confidence += 0.3
        }
        
        if !actionItems.isEmpty {
            confidence += 0.2
        }
        
        if !participants.isEmpty {
            confidence += 0.1
        }
        
        return min(confidence, 1.0)
    }
    
    private func notifyCommitmentsDetected(_ commitments: [String], appName: String) async {
        guard let bus = communicationBus else { return }
        
        for commitment in commitments {
            let commitmentInfo = CommitmentInfo(
                commitmentId: UUID(),
                description: commitment,
                participants: extractChatParticipants(commitment),
                deadline: nil,
                source: .screenCapture(appName),
                confidence: 0.7
            )
            
            let message = AgentMessage(
                type: .commitmentDetected,
                from: specialization,
                content: .commitment(commitmentInfo),
                priority: .high
            )
            
            await bus.broadcast(message)
        }
    }
}

/// Action Prioritizer Agent
@MainActor
class ActionPrioritizerAgent: BaseAIAgent {
    private var actionQueue: [PrioritizedAction] = []
    
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .actionPrioritizer,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        let action = PrioritizedAction(
            id: UUID(),
            description: task.description,
            priority: task.priority,
            deadline: task.deadline,
            createdDate: Date(),
            source: task.parameters["source"] as? String ?? "unknown"
        )
        
        // Add to queue and sort by priority
        actionQueue.append(action)
        actionQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        // Limit queue size
        if actionQueue.count > 50 {
            actionQueue = Array(actionQueue.prefix(50))
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "actionId": action.id,
                "queuePosition": actionQueue.firstIndex(where: { $0.id == action.id }) ?? -1,
                "queueSize": actionQueue.count
            ],
            confidence: 0.9,
            suggestedActions: [],
            error: nil
        )
    }
    
    func getTopActions(limit: Int = 10) -> [PrioritizedAction] {
        return Array(actionQueue.prefix(limit))
    }
}

/// Meeting Transcriber Agent
@MainActor
class MeetingTranscriberAgent: BaseAIAgent {
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .meetingTranscriber,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let transcript = task.parameters["transcript"] as? String,
              let participants = task.parameters["participants"] as? [String] else {
            throw AgentError.invalidTask
        }
        
        // Extract action items and decisions from transcript
        let analysis = analyzeMeetingTranscript(transcript, participants: participants)
        
        // Notify about action items
        for actionItem in analysis.actionItems {
            await notifyActionItem(actionItem, participants: participants)
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "actionItems": analysis.actionItems,
                "decisions": analysis.decisions,
                "keyTopics": analysis.keyTopics
            ],
            confidence: 0.8,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func analyzeMeetingTranscript(_ transcript: String, participants: [String]) -> MeetingAnalysis {
        var actionItems: [String] = []
        var decisions: [String] = []
        var keyTopics: [String] = []
        
        let sentences = transcript.components(separatedBy: .newlines)
        
        for sentence in sentences {
            let lowercased = sentence.lowercased()
            
            // Look for action items
            if lowercased.contains("action item") || lowercased.contains("will do") || 
               lowercased.contains("needs to") || lowercased.contains("should") {
                actionItems.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            // Look for decisions
            if lowercased.contains("decided") || lowercased.contains("agreed") || 
               lowercased.contains("conclusion") {
                decisions.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        // Extract key topics (simplified)
        let words = transcript.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let wordCounts = Dictionary(grouping: words, by: { $0 }).mapValues { $0.count }
        keyTopics = wordCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { $0.key.count > 3 ? $0.key : nil }
        
        return MeetingAnalysis(
            actionItems: actionItems,
            decisions: decisions,
            keyTopics: keyTopics
        )
    }
    
    private func notifyActionItem(_ actionItem: String, participants: [String]) async {
        guard let bus = communicationBus else { return }
        
        let actionInfo = ActionInfo(
            actionId: UUID(),
            description: actionItem,
            urgency: .medium,
            dueDate: Date().addingTimeInterval(86400), // 24 hours
            relatedCommitmentId: nil
        )
        
        let message = AgentMessage(
            type: .actionRequired,
            from: specialization,
            content: .action(actionInfo),
            priority: .normal
        )
        
        await bus.broadcast(message)
    }
}

/// Search Coordinator Agent
@MainActor
class SearchCoordinatorAgent: BaseAIAgent {
    init(communicationBus: AgentCommunicationBus?) {
        super.init(
            specialization: .searchCoordinator,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        guard let query = task.parameters["query"] as? String else {
            throw AgentError.invalidTask
        }
        
        // This is a placeholder - in practice this would coordinate
        // searches across clipboard, browser history, etc.
        let results = await performCoordinatedSearch(query)
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: ["searchResults": results],
            confidence: 0.7,
            suggestedActions: [],
            error: nil
        )
    }
    
    private func performCoordinatedSearch(_ query: String) async -> [String: Any] {
        // Placeholder for coordinated search implementation
        return [
            "clipboardResults": [],
            "browserResults": [],
            "conversationResults": []
        ]
    }
}

// MARK: - Supporting Data Models

struct AgentScreenAnalysis {
    let commitments: [String]
    let actionItems: [String]
    let participants: [String]
    let urgencyLevel: ProcessingPriority
    let confidence: Double
}

struct PrioritizedAction: Identifiable {
    let id: UUID
    let description: String
    let priority: ProcessingPriority
    let deadline: Date?
    let createdDate: Date
    let source: String
}

struct MeetingAnalysis {
    let actionItems: [String]
    let decisions: [String]
    let keyTopics: [String]
}