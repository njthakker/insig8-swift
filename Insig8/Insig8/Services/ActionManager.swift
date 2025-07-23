//
//  ActionManager.swift
//  Insig8
//
//  Core action and commitment tracking system for AI-driven follow-ups
//

import Foundation
import Combine
import os.log

// Local type definitions to avoid conflicts
enum ActionFollowupType: String, Codable {
    case emailFollowup = "email_followup"
    case messageFollowup = "message_followup"
    case meetingFollowup = "meeting_followup"
}

struct MeetingActionItemLocal {
    let text: String
    let assignee: String?
    let dueDate: String?
    let priority: Int
    
    // Helper properties for action creation
    var title: String {
        return String(text.prefix(50))
    }
    
    var description: String {
        return text
    }
    
    var isAssignedToUser: Bool {
        let userIndicators = ["I will", "I'll", "I can", "I should", "my responsibility"]
        let lower = text.lowercased()
        return userIndicators.contains { lower.contains($0) }
    }
    
    var fullContext: String {
        return text
    }
}

@MainActor
class ActionManager: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Insig8", category: "ActionManager")
    
    // Published properties for UI updates
    @Published var activeActions: [Action] = []
    @Published var completedActions: [Action] = []
    @Published var urgentActions: [Action] = []
    @Published var pendingFollowups: [Followup] = []
    
    // Dependencies
    private let sqliteDB: SQLiteVectorDatabase
    private let secureStorage: SecureAIStorage
    private var cancellables = Set<AnyCancellable>()
    
    // Background monitoring
    private var responseCheckTimer: Timer?
    private let actionQueue = DispatchQueue(label: "ai.insig8.actions", qos: .userInitiated)
    
    init(sqliteDB: SQLiteVectorDatabase, secureStorage: SecureAIStorage) {
        self.sqliteDB = sqliteDB
        self.secureStorage = secureStorage
        
        setupTimers()
        loadPersistedActions()
    }
    
    // MARK: - Core Action Management
    
    /// Create action from unresponded message detected by screen capture
    func createAction(from message: UnrespondedMessage, context: ScreenContext) -> Action {
        let action = Action(
            id: UUID(),
            type: .response,
            title: "Respond to \(message.sender ?? "Unknown")",
            description: extractActionDescription(from: message.content),
            source: .screenCapture(app: message.appName),
            priority: message.urgencyLevel,
            createdAt: Date(),
            dueDate: calculateDueDate(for: message.urgencyLevel),
            context: ActionContext(
                appName: message.appName,
                contactName: message.sender,
                originalMessage: message.content,
                channelOrThread: context.channelName,
                messageTimestamp: message.timestamp
            )
        )
        
        addAction(action)
        logger.info("Created action for \(message.appName): \(action.title)")
        return action
    }
    
    /// Create action from commitment detected in outgoing message
    func createCommitmentAction(from text: String, context: ScreenContext) -> Action? {
        guard let commitment = extractCommitment(from: text) else { return nil }
        
        let action = Action(
            id: UUID(),
            type: .commitment,
            title: "Follow up on commitment: \(commitment.summary)",
            description: commitment.fullText,
            source: .screenCapture(app: context.appName),
            priority: .medium,
            createdAt: Date(),
            dueDate: commitment.estimatedDueDate ?? Date().addingTimeInterval(3 * 3600), // 3 hours default
            context: ActionContext(
                appName: context.appName,
                contactName: commitment.recipient,
                originalMessage: text,
                channelOrThread: context.channelName,
                messageTimestamp: Date()
            )
        )
        
        addAction(action)
        logger.info("Created commitment action: \(action.title)")
        return action
    }
    
    /// Mark action as completed when response is detected
    func markActionCompleted(actionId: UUID, responseText: String, detectedAt: Date) {
        guard let index = activeActions.firstIndex(where: { $0.id == actionId }) else { return }
        
        var action = activeActions[index]
        action.status = .completed
        action.completedAt = detectedAt
        action.responseText = responseText
        
        activeActions.remove(at: index)
        completedActions.append(action)
        
        // Remove from urgent if present
        urgentActions.removeAll { $0.id == actionId }
        
        persistActions()
        logger.info("Marked action completed: \(action.title)")
    }
    
    /// Check for responses in new screen content
    func checkForResponses(in screenContent: ProcessedScreenContent) {
        let activeActionsForApp = activeActions.filter { 
            $0.context?.appName == screenContent.appName 
        }
        
        for action in activeActionsForApp {
            if let response = detectResponse(to: action, in: screenContent) {
                markActionCompleted(
                    actionId: action.id,
                    responseText: response,
                    detectedAt: screenContent.timestamp
                )
            }
        }
    }
    
    // MARK: - Email-Specific Actions
    
    /// Create action for unanswered email
    func createEmailAction(subject: String, sender: String, receivedAt: Date) -> Action {
        let action = Action(
            id: UUID(),
            type: .response,
            title: "Reply to email from \(sender)",
            description: "Email: \(subject)",
            source: .email,
            priority: calculateEmailPriority(subject: subject, sender: sender),
            createdAt: Date(),
            dueDate: receivedAt.addingTimeInterval(4 * 3600), // 4 hours for emails
            context: ActionContext(
                appName: "Mail",
                contactName: sender,
                originalMessage: subject,
                channelOrThread: nil,
                messageTimestamp: receivedAt
            )
        )
        
        addAction(action)
        return action
    }
    
    /// Create followup reminder for email thread
    func createEmailFollowup(originalSubject: String, recipient: String, lastSentAt: Date, followupDays: Int = 3) -> Followup {
        let followup = Followup(
            id: UUID(),
            type: ActionFollowupType.emailFollowup,
            title: "Follow up with \(recipient)",
            description: "No response to: \(originalSubject)",
            recipient: recipient,
            originalDate: lastSentAt,
            dueDate: lastSentAt.addingTimeInterval(TimeInterval(followupDays * 24 * 3600)),
            priority: .medium
        )
        
        pendingFollowups.append(followup)
        logger.info("Created email followup for \(recipient)")
        return followup
    }
    
    // MARK: - Meeting Actions
    
    /// Create actions from meeting transcript analysis
    func createMeetingActions(from transcript: String, participants: [String], meetingTitle: String?) -> [Action] {
        let actionItems = extractMeetingActionItems(from: transcript)
        var actions: [Action] = []
        
        for item in actionItems {
            let action = Action(
                id: UUID(),
                type: item.isAssignedToUser ? .task : .followup,
                title: item.title,
                description: item.description,
                source: .meeting(title: meetingTitle ?? "Meeting"),
                priority: convertIntToPriority(item.priority),
                createdAt: Date(),
                dueDate: parseDateFromString(item.dueDate) ?? Date().addingTimeInterval(24 * 3600), // 1 day default
                context: ActionContext(
                    appName: "Meeting",
                    contactName: item.assignee,
                    originalMessage: item.fullContext,
                    channelOrThread: meetingTitle,
                    messageTimestamp: Date()
                )
            )
            
            actions.append(action)
            addAction(action)
        }
        
        logger.info("Created \(actions.count) actions from meeting transcript")
        return actions
    }
    
    // MARK: - Action Modification
    
    /// User can modify action properties
    func modifyAction(_ actionId: UUID, modification: ActionModification) {
        guard let index = activeActions.firstIndex(where: { $0.id == actionId }) else { return }
        
        switch modification {
        case .changeDueDate(let newDate):
            activeActions[index].dueDate = newDate
        case .changePriority(let newPriority):
            activeActions[index].priority = newPriority
            updateUrgentActions()
        case .snooze(let duration):
            activeActions[index].dueDate = Date().addingTimeInterval(duration)
        case .dismiss:
            activeActions[index].status = .dismissed
            activeActions.remove(at: index)
        case .addDescription(let description):
            activeActions[index].description += "\n\nUser Note: \(description)"
        }
        
        persistActions()
        logger.info("Modified action \(actionId): \(modification.description)")
    }
    
    // MARK: - Private Implementation
    
    func addAction(_ action: Action) {
        activeActions.append(action)
        
        if action.priority == .urgent || isOverdue(action) {
            urgentActions.append(action)
        }
        
        persistActions()
    }
    
    private func setupTimers() {
        // Check for overdue actions every 5 minutes
        responseCheckTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                self.updateUrgentActions()
                self.checkFollowupsDue()
            }
        }
    }
    
    private func updateUrgentActions() {
        urgentActions = activeActions.filter { action in
            action.priority == .urgent || isOverdue(action)
        }
    }
    
    private func isOverdue(_ action: Action) -> Bool {
        return action.dueDate < Date()
    }
    
    private func checkFollowupsDue() {
        let dueFollowups = pendingFollowups.filter { $0.dueDate <= Date() }
        for followup in dueFollowups {
            // Convert followup to action for user attention
            let action = Action(
                id: UUID(),
                type: .followup,
                title: followup.title,
                description: followup.description,
                source: .followup,
                priority: followup.priority,
                createdAt: Date(),
                dueDate: followup.dueDate,
                context: ActionContext(
                    appName: "Followup",
                    contactName: followup.recipient,
                    originalMessage: followup.description,
                    channelOrThread: nil,
                    messageTimestamp: followup.originalDate
                )
            )
            
            addAction(action)
            
            // Remove from pending
            pendingFollowups.removeAll { $0.id == followup.id }
        }
    }
    
    private func calculateDueDate(for priority: Priority) -> Date {
        let now = Date()
        switch priority {
        case .urgent:
            return now.addingTimeInterval(30 * 60) // 30 minutes
        case .high:
            return now.addingTimeInterval(2 * 3600) // 2 hours
        case .medium:
            return now.addingTimeInterval(4 * 3600) // 4 hours
        case .low:
            return now.addingTimeInterval(24 * 3600) // 1 day
        }
    }
    
    private func extractCommitment(from text: String) -> CommitmentParsed? {
        let commitmentPatterns = [
            "I'll get back to you",
            "I will look into",
            "I'll check",
            "I'll follow up",
            "I'll send",
            "I'll review",
            "I will investigate",
            "let me check",
            "let me look into"
        ]
        
        let lowercased = text.lowercased()
        
        for pattern in commitmentPatterns {
            if lowercased.contains(pattern) {
                return CommitmentParsed(
                    summary: pattern,
                    fullText: text,
                    recipient: extractRecipient(from: text),
                    estimatedDueDate: extractTimeReference(from: text)
                )
            }
        }
        
        return nil
    }
    
    private func detectResponse(to action: Action, in screenContent: ProcessedScreenContent) -> String? {
        guard let context = action.context,
              let originalContact = context.contactName else { return nil }
        
        // Look for messages in the same app/channel containing response indicators
        for message in screenContent.parsedContent.messages {
            // Check if this is from the user (not the original sender)
            if message.sender != originalContact {
                // Look for response patterns
                let responsePatterns = [
                    "here's what I found",
                    "I looked into",
                    "after checking",
                    "the answer is",
                    "I investigated",
                    "here are the details"
                ]
                
                let messageText = message.content.lowercased()
                for pattern in responsePatterns {
                    if messageText.contains(pattern) {
                        return message.content
                    }
                }
                
                // Also check if message is in response to the original message context
                if messageText.contains(context.originalMessage?.lowercased() ?? "") {
                    return message.content
                }
            }
        }
        
        return nil
    }
    
    private func extractActionDescription(from content: String) -> String {
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? content
        
        if firstSentence.count > 100 {
            return String(firstSentence.prefix(97)) + "..."
        }
        
        return firstSentence
    }
    
    private func calculateEmailPriority(subject: String, sender: String) -> Priority {
        let urgentKeywords = ["urgent", "asap", "immediate", "critical"]
        let highKeywords = ["important", "priority", "deadline"]
        
        let subjectLower = subject.lowercased()
        
        if urgentKeywords.contains(where: { subjectLower.contains($0) }) {
            return .urgent
        }
        
        if highKeywords.contains(where: { subjectLower.contains($0) }) {
            return .high
        }
        
        // VIP senders (could be configured by user)
        let vipSenders = ["boss", "ceo", "manager"] // Simplified
        if vipSenders.contains(where: { sender.lowercased().contains($0) }) {
            return .high
        }
        
        return .medium
    }
    
    private func extractMeetingActionItems(from transcript: String) -> [MeetingActionItemLocal] {
        var items: [MeetingActionItemLocal] = []
        
        let actionPatterns = [
            "action item:",
            "todo:",
            "follow up on",
            "will take care of",
            "assigned to",
            "responsible for"
        ]
        
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let lower = sentence.lowercased()
            
            for pattern in actionPatterns {
                if lower.contains(pattern) {
                    let item = MeetingActionItemLocal(
                        text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        assignee: extractAssignee(from: sentence),
                        dueDate: extractTimeReference(from: sentence)?.timeIntervalSince1970.description,
                        priority: 2 // medium priority as Int
                    )
                    items.append(item)
                    break
                }
            }
        }
        
        return items
    }
    
    private func extractRecipient(from text: String) -> String? {
        // Simple extraction - in production, would use NLP
        let words = text.components(separatedBy: .whitespaces)
        
        // Look for names after "to", "@", or at the beginning
        for (index, word) in words.enumerated() {
            if word.lowercased() == "to" && index + 1 < words.count {
                return words[index + 1]
            }
            if word.starts(with: "@") {
                return String(word.dropFirst())
            }
        }
        
        return nil
    }
    
    private func extractTimeReference(from text: String) -> Date? {
        let timeKeywords = [
            "shortly": 1800, // 30 minutes
            "soon": 3600, // 1 hour
            "today": 6 * 3600, // 6 hours
            "tomorrow": 24 * 3600, // 1 day
            "this week": 5 * 24 * 3600, // 5 days
            "next week": 7 * 24 * 3600 // 1 week
        ]
        
        let lower = text.lowercased()
        
        for (keyword, seconds) in timeKeywords {
            if lower.contains(keyword) {
                return Date().addingTimeInterval(TimeInterval(seconds))
            }
        }
        
        return nil
    }
    
    private func extractActionTitle(from sentence: String) -> String {
        let cleanSentence = sentence.replacingOccurrences(of: "action item:", with: "")
            .replacingOccurrences(of: "todo:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanSentence.count > 50 {
            return String(cleanSentence.prefix(47)) + "..."
        }
        
        return cleanSentence
    }
    
    private func extractAssignee(from sentence: String) -> String? {
        // Look for "assigned to X" or similar patterns
        if let range = sentence.range(of: "assigned to ", options: .caseInsensitive) {
            let remainder = String(sentence[range.upperBound...])
            return remainder.components(separatedBy: .whitespaces).first
        }
        
        return nil
    }
    
    private func isAssignedToCurrentUser(_ sentence: String) -> Bool {
        let userIndicators = ["I will", "I'll", "I can", "I should", "my responsibility"]
        let lower = sentence.lowercased()
        
        return userIndicators.contains { lower.contains($0) }
    }
    
    private func persistActions() {
        // Store actions in secure storage for persistence across app launches
        Task {
            do {
                let actionsData = try JSONEncoder().encode(ActiveActionsContainer(
                    active: activeActions,
                    completed: Array(completedActions.suffix(50)), // Keep last 50 completed
                    followups: pendingFollowups
                ))
                
                // Store encrypted
                let encryptedData = try secureStorage.encrypt(actionsData)
                UserDefaults.standard.set(encryptedData, forKey: "user_actions")
            } catch {
                logger.error("Failed to persist actions: \(error)")
            }
        }
    }
    
    private func loadPersistedActions() {
        Task {
            do {
                if let encryptedData = UserDefaults.standard.data(forKey: "user_actions") {
                    let data = try secureStorage.decrypt(encryptedData)
                    let container = try JSONDecoder().decode(ActiveActionsContainer.self, from: data)
                    
                    await MainActor.run {
                        self.activeActions = container.active
                        self.completedActions = container.completed
                        self.pendingFollowups = container.followups
                        self.updateUrgentActions()
                    }
                    
                    logger.info("Loaded \(self.activeActions.count) persisted actions")
                }
            } catch {
                logger.error("Failed to load persisted actions: \(error)")
            }
        }
    }
    
    private func convertIntToPriority(_ value: Int) -> Priority {
        switch value {
        case 0:
            return .low
        case 1:
            return .medium
        case 2:
            return .high
        case 3:
            return .urgent
        default:
            return .medium
        }
    }
    
    private func parseDateFromString(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        // Try to parse as timestamp
        if let timestamp = Double(dateString) {
            return Date(timeIntervalSince1970: timestamp)
        }
        
        // Return nil for non-parseable strings
        return nil
    }
}

// MARK: - Supporting Types

struct Action: Codable, Identifiable {
    let id: UUID
    let type: ActionType
    var title: String
    var description: String
    let source: ActionSource
    var priority: Priority
    let createdAt: Date
    var dueDate: Date
    var status: ActionStatus = .active
    var completedAt: Date?
    var responseText: String?
    var context: ActionContext?
}

enum ActionType: String, Codable {
    case response = "response"
    case commitment = "commitment"
    case task = "task"
    case followup = "followup"
}

enum ActionSource: Codable {
    case screenCapture(app: String)
    case email
    case meeting(title: String)
    case followup
    case manual
}

enum ActionStatus: String, Codable {
    case active = "active"
    case completed = "completed"
    case dismissed = "dismissed"
    case snoozed = "snoozed"
}

struct ActionContext: Codable {
    let appName: String
    let contactName: String?
    let originalMessage: String?
    let channelOrThread: String?
    let messageTimestamp: Date?
}

enum ActionModification: CustomStringConvertible {
    case changeDueDate(Date)
    case changePriority(Priority)
    case snooze(TimeInterval)
    case dismiss
    case addDescription(String)
    
    var description: String {
        switch self {
        case .changeDueDate(let date):
            return "changeDueDate(\(date))"
        case .changePriority(let priority):
            return "changePriority(\(priority))"
        case .snooze(let interval):
            return "snooze(\(interval)s)"
        case .dismiss:
            return "dismiss"
        case .addDescription(let desc):
            return "addDescription(\(desc))"
        }
    }
}

struct Followup: Codable, Identifiable {
    let id: UUID
    let type: ActionFollowupType
    let title: String
    let description: String
    let recipient: String
    let originalDate: Date
    let dueDate: Date
    let priority: Priority
}

struct ScreenContext {
    let appName: String
    let channelName: String?
    let windowTitle: String?
}

struct CommitmentParsed {
    let summary: String
    let fullText: String
    let recipient: String?
    let estimatedDueDate: Date?
}

struct ActiveActionsContainer: Codable {
    let active: [Action]
    let completed: [Action]
    let followups: [Followup]
}