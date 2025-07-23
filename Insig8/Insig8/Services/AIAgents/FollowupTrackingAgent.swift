import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Followup Tracking Agent
class FollowupTrackingAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "FollowupAgent")
    weak var delegate: AIAgentDelegate?
    
    #if canImport(FoundationModels)
    private var aiSession: LanguageModelSession?
    #endif
    
    // Tracking active followups
    private var activeFollowups: [UUID: FollowupTracker] = [:]
    
    init() {
        setupAISession()
        startFollowupMonitoring()
    }
    
    private func setupAISession() {
        #if canImport(FoundationModels)
        aiSession = LanguageModelSession {
            """
            You are a followup tracking AI. Analyze communications to identify when followups are needed.
            
            Look for patterns indicating followup requirements:
            - Unanswered questions
            - Emails requiring responses
            - Messages waiting for replies
            - Commitments that need verification
            - Requests that need acknowledgment
            
            Determine the appropriate followup timeline based on context and urgency.
            """
        }
        #endif
    }
    
    func trackFollowup(_ item: ProcessingItem, tags: [ContentTag]) async {
        logger.info("Tracking followup for: \(item.source)")
        
        #if canImport(FoundationModels)
        if let session = aiSession, !session.isResponding {
            await processWithAI(item, session: session, tags: tags)
        } else {
            await processWithRules(item, tags: tags)
        }
        #else
        await processWithRules(item, tags: tags)
        #endif
    }
    
    #if canImport(FoundationModels)
    private func processWithAI(_ item: ProcessingItem, session: LanguageModelSession, tags: [ContentTag]) async {
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this content for followup requirements: "\(item.content)"
                
                Source: \(item.source)
                Tags: \(tags.map { $0.rawValue }.joined(separator: ", "))
                
                Determine:
                1. What type of followup is needed?
                2. Who should be followed up with?
                3. When should the followup occur?
                4. What is the urgency level?
                5. What context should be included in the followup?
                """,
                generating: FollowupAnalysisResult.self
            )
            
            if analysis.content.needsFollowup {
                let followupTask = createFollowupTask(from: analysis.content, item: item, tags: tags)
                delegate?.agentDidCreateTask(followupTask)
                
                // Track for monitoring
                let tracker = FollowupTracker(
                    id: followupTask.id,
                    originalContent: item.content,
                    source: item.source,
                    expectedResponseTime: followupTask.dueDate ?? Date().addingTimeInterval(3600 * 3),
                    recipient: analysis.content.recipient,
                    followupType: AgentFollowupType(rawValue: analysis.content.followupType) ?? .general
                )
                
                activeFollowups[followupTask.id] = tracker
            }
            
        } catch {
            logger.error("AI followup analysis failed: \(error.localizedDescription)")
            await processWithRules(item, tags: tags)
        }
    }
    #endif
    
    private func processWithRules(_ item: ProcessingItem, tags: [ContentTag]) async {
        var needsFollowup = false
        var followupType: AgentFollowupType = .general
        var recipient: String = "Unknown"
        var deadline: Date?
        
        let content = item.content.lowercased()
        
        // Determine if followup is needed based on source and content
        switch item.source {
        case .email(let sender, _):
            if content.contains("?") || content.contains("please") || content.contains("can you") {
                needsFollowup = true
                followupType = .emailResponse
                recipient = sender ?? "Unknown"
                deadline = Date().addingTimeInterval(3600 * 4) // 4 hours for email
            }
            
        case .screenCapture(let appName):
            if (appName.lowercased().contains("slack") || appName.lowercased().contains("teams")) {
                if content.contains("@") || tags.contains(.question) {
                    needsFollowup = true
                    followupType = .messageResponse
                    deadline = Date().addingTimeInterval(3600 * 3) // 3 hours for messages
                }
            }
            
        case .meeting:
            if tags.contains(.action_item) {
                needsFollowup = true
                followupType = .actionItemCheck
                deadline = Date().addingTimeInterval(3600 * 24) // 24 hours for action items
            }
            
        default:
            if tags.contains(.commitment) {
                needsFollowup = true
                followupType = .commitmentVerification
                deadline = Date().addingTimeInterval(3600 * 6) // 6 hours for commitments
            }
        }
        
        if needsFollowup {
            let task = AITask(
                id: UUID(),
                description: generateFollowupDescriptionForItem(item: item, type: followupType, recipient: recipient),
                source: item.source,
                tags: [.followup_required, .reminder] + tags,
                priority: determineFollowupPriority(type: followupType, content: content),
                status: .pending,
                dueDate: deadline,
                createdDate: Date(),
                modifiedDate: Date(),
                relevanceScore: 0.8
            )
            
            delegate?.agentDidCreateTask(task)
            
            // Track for monitoring
            let tracker = FollowupTracker(
                id: task.id,
                originalContent: item.content,
                source: item.source,
                expectedResponseTime: deadline ?? Date().addingTimeInterval(3600),
                recipient: recipient,
                followupType: followupType
            )
            
            activeFollowups[task.id] = tracker
        }
    }
    
    private func startFollowupMonitoring() {
        // Check followups every 30 minutes
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task {
                await self.checkOverdueFollowups()
            }
        }
    }
    
    private func checkOverdueFollowups() async {
        let now = Date()
        
        for (taskId, tracker) in activeFollowups {
            if now > tracker.expectedResponseTime {
                // Create overdue followup task
                let overdueTask = AITask(
                    id: UUID(),
                    description: "OVERDUE: \(generateFollowupDescription(tracker: tracker))",
                    source: tracker.source,
                    tags: [.urgent_action, .followup_required, .reminder],
                    priority: .urgent,
                    status: .pending,
                    dueDate: now,
                    createdDate: now,
                    modifiedDate: now,
                    relevanceScore: 1.0
                )
                
                delegate?.agentDidCreateTask(overdueTask)
                
                // Remove from active tracking
                activeFollowups.removeValue(forKey: taskId)
                
                logger.warning("Created overdue followup task for: \(tracker.recipient)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateFollowupDescriptionForItem(item: ProcessingItem, type: AgentFollowupType, recipient: String) -> String {
        switch type {
        case .emailResponse:
            return "Follow up on email response to \(recipient)"
        case .messageResponse:
            return "Check if you responded to \(recipient)'s message"
        case .commitmentVerification:
            return "Verify completion of commitment to \(recipient)"
        case .actionItemCheck:
            return "Check progress on action item from meeting"
        case .general:
            return "Follow up on communication with \(recipient)"
        }
    }
    
    private func generateFollowupDescription(tracker: FollowupTracker) -> String {
        let item = ProcessingItem(id: UUID(), content: tracker.originalContent, source: tracker.source, timestamp: Date(), priority: .medium)
        return generateFollowupDescriptionForItem(item: item, type: tracker.followupType, recipient: tracker.recipient)
    }
    
    private func determineFollowupPriority(type: AgentFollowupType, content: String) -> ProcessingPriority {
        if content.contains("urgent") || content.contains("asap") {
            return .urgent
        }
        
        switch type {
        case .emailResponse:
            return .high
        case .messageResponse:
            return .medium
        case .commitmentVerification:
            return .high
        case .actionItemCheck:
            return .medium
        case .general:
            return .medium
        }
    }
    
    #if canImport(FoundationModels)
    private func createFollowupTask(from analysis: FollowupAnalysisResult, item: ProcessingItem, tags: [ContentTag]) -> AITask {
        return AITask(
            id: UUID(),
            description: analysis.followupAction,
            source: item.source,
            tags: [.followup_required, .reminder] + tags,
            priority: ProcessingPriority(rawValue: analysis.urgencyLevel) ?? .medium,
            status: .pending,
            dueDate: parseDateString(analysis.suggestedFollowupTime),
            createdDate: Date(),
            modifiedDate: Date(),
            relevanceScore: Float(analysis.confidence)
        )
    }
    
    private func parseDateString(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Handle natural language
        let now = Date()
        let lowercased = dateString.lowercased()
        
        if lowercased.contains("3 hours") {
            return Calendar.current.date(byAdding: .hour, value: 3, to: now)
        } else if lowercased.contains("tomorrow") {
            return Calendar.current.date(byAdding: .day, value: 1, to: now)
        } else if lowercased.contains("3 days") {
            return Calendar.current.date(byAdding: .day, value: 3, to: now)
        } else {
            return Calendar.current.date(byAdding: .hour, value: 4, to: now)
        }
    }
    #endif
    
    // Mark followup as completed
    func markFollowupCompleted(_ taskId: UUID) {
        activeFollowups.removeValue(forKey: taskId)
        logger.info("Followup completed and removed from tracking: \(taskId)")
    }
}

// MARK: - Supporting Data Structures

struct FollowupTracker {
    let id: UUID
    let originalContent: String
    let source: ContentSource
    let expectedResponseTime: Date
    let recipient: String
    let followupType: AgentFollowupType
}

enum AgentFollowupType: String, Codable {
    case emailResponse = "email_response"
    case messageResponse = "message_response"
    case commitmentVerification = "commitment_verification"
    case actionItemCheck = "action_item_check"
    case general = "general"
}

#if canImport(FoundationModels)
@Generable
struct FollowupAnalysisResult: Codable {
    @Guide(description: "Whether a followup is needed")
    let needsFollowup: Bool
    
    @Guide(description: "Type of followup required")
    let followupType: String
    
    @Guide(description: "Who to follow up with")
    let recipient: String
    
    @Guide(description: "When to follow up (ISO8601 or natural language)")
    let suggestedFollowupTime: String?
    
    @Guide(description: "Urgency level: 1=low, 2=medium, 3=high, 4=urgent")
    let urgencyLevel: Int
    
    @Guide(description: "Description of the followup action needed")
    let followupAction: String
    
    @Guide(description: "Context to include in the followup")
    let contextInfo: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}
#endif