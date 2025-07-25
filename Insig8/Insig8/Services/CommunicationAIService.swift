import SwiftUI
import Combine
import OSLog
import UserNotifications

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Communication AI Service for Smart Reminders
@MainActor
class CommunicationAIService: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "CommunicationAI")
    
    // Published state
    @Published var activeCommitments: [Commitment] = []
    @Published var pendingReminders: [CommCommSmartReminder] = []
    @Published var emailThreads: [EmailThread] = []
    @Published var isProcessing = false
    
    // AI Session for communication analysis
#if canImport(FoundationModels)
    private var communicationSession: LanguageModelSession?
#endif
    
    // Reminder scheduling
    private var reminderTimer: Timer?
    
    init() {
        setupCommunicationAI()
        loadPersistedData()
        startReminderEngine()
        requestNotificationPermissions()
    }
    
    deinit {
        reminderTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupCommunicationAI() {
#if canImport(FoundationModels)
        communicationSession = LanguageModelSession {
            """
            You are an AI assistant specialized in analyzing communications (emails, messages, meetings) to identify:
            1. Commitments and promises made by the user
            2. Questions that need responses
            3. Follow-up actions required
            4. Urgency levels and deadlines
            5. People involved and their roles
            
            Focus on productivity and helping users stay on top of their communications.
            Be precise in identifying actionable items and realistic about deadlines.
            """
        }
#endif
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                self.logger.info("Notification permissions granted")
            } else {
                self.logger.warning("Notification permissions denied")
            }
        }
    }
    
    // MARK: - Communication Analysis
    
    func analyzeEmailContent(_ content: String, sender: String?, subject: String?) async -> CommunicationAnalysis? {
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        guard let session = communicationSession else {
            return analyzeEmailWithRules(content, sender: sender, subject: subject)
        }
        
        // Check if session is already responding
        guard !session.isResponding else {
            logger.warning("Communication AI session is busy, falling back to rule-based analysis")
            return analyzeEmailWithRules(content, sender: sender, subject: subject)
        }
        
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this email for actionable items:
                
                From: \(sender ?? "Unknown")
                Subject: \(subject ?? "No subject")
                Content: \(content)
                
                Identify:
                1. Does this email require a response? (true/false)
                2. Any commitments made by the sender or expected from recipient
                3. Urgency level (1-4: low to urgent)
                4. Suggested response deadline
                5. Key action items or questions
                6. People mentioned who might need follow-up
                """,
                generating: EmailAnalysisResult.self
            )
            
            return CommunicationAnalysis(
                requiresResponse: analysis.content.requiresResponse,
                commitments: analysis.content.commitments,
                urgencyLevel: Priority(rawValue: analysis.content.urgencyLevel) ?? .medium,
                suggestedDeadline: parseDateString(analysis.content.suggestedDeadline),
                actionItems: analysis.content.actionItems,
                involvedPeople: analysis.content.involvedPeople,
                confidence: analysis.content.confidence,
                source: .email
            )
        } catch {
            logger.error("Foundation Models email analysis failed: \(error.localizedDescription)")
            return analyzeEmailWithRules(content, sender: sender, subject: subject)
        }
#else
        return analyzeEmailWithRules(content, sender: sender, subject: subject)
#endif
    }
    
    func analyzeMessageContent(_ content: String, sender: String?, platform: String, channel: String?) async -> CommunicationAnalysis? {
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        guard let session = communicationSession else {
            return analyzeMessageWithRules(content, sender: sender, platform: platform)
        }
        
        // Check if session is already responding
        guard !session.isResponding else {
            logger.warning("Communication AI session is busy, falling back to rule-based analysis")
            return analyzeMessageWithRules(content, sender: sender, platform: platform)
        }
        
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this \(platform) message for actionable items:
                
                From: \(sender ?? "Unknown")
                Channel: \(channel ?? "Direct message")
                Content: \(content)
                
                Identify:
                1. Does this message require a response? (true/false)
                2. Any commitments or requests made
                3. Urgency level (1-4: low to urgent)
                4. Suggested response timeframe
                5. Key action items
                6. Context and importance
                """,
                generating: MessageAnalysisResult.self
            )
            
            return CommunicationAnalysis(
                requiresResponse: analysis.content.requiresResponse,
                commitments: analysis.content.commitments,
                urgencyLevel: Priority(rawValue: analysis.content.urgencyLevel) ?? .medium,
                suggestedDeadline: parseDateString(analysis.content.suggestedTimeframe),
                actionItems: analysis.content.actionItems,
                involvedPeople: [sender].compactMap { $0 },
                confidence: analysis.content.confidence,
                source: platform == "slack" ? .slack : (platform == "teams" ? .teams : .manual)
            )
        } catch {
            logger.error("Foundation Models message analysis failed: \(error.localizedDescription)")
            return analyzeMessageWithRules(content, sender: sender, platform: platform)
        }
#else
        return analyzeMessageWithRules(content, sender: sender, platform: platform)
#endif
    }
    
    func analyzeMeetingTranscript(_ transcript: String, participants: [String], title: String?) async -> [ActionItem] {
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        guard let session = communicationSession else {
            return analyzeMeetingWithRules(transcript, participants: participants)
        }
        
        // Check if session is already responding
        guard !session.isResponding else {
            logger.warning("Communication AI session is busy, falling back to rule-based analysis")
            return analyzeMeetingWithRules(transcript, participants: participants)
        }
        
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this meeting transcript for action items:
                
                Meeting: \(title ?? "Untitled Meeting")
                Participants: \(participants.joined(separator: ", "))
                Transcript: \(transcript)
                
                Extract:
                1. Specific action items mentioned
                2. Who is assigned to each task
                3. Due dates or deadlines mentioned
                4. Priority levels
                5. Dependencies between tasks
                6. Follow-up meetings or check-ins needed
                """,
                generating: MeetingAnalysisResult.self
            )
            
            return analysis.content.actionItems.map { item in
                ActionItem(
                    id: UUID(),
                    text: item.text,
                    assignee: item.assignee,
                    dueDate: parseDateString(item.dueDate),
                    priority: Priority(rawValue: item.priority) ?? .medium,
                    status: .open,
                    sourceType: .meeting,
                    relatedMeeting: nil,
                    relatedCommitment: nil,
                    userModified: false,
                    createdDate: Date()
                )
            }
        } catch {
            logger.error("Foundation Models meeting analysis failed: \(error.localizedDescription)")
            return analyzeMeetingWithRules(transcript, participants: participants)
        }
#else
        return analyzeMeetingWithRules(transcript, participants: participants)
#endif
    }
    
    // MARK: - Commitment Tracking
    
    func addCommitment(_ analysis: CommunicationAnalysis, originalContent: String) {
        for commitmentText in analysis.commitments {
            let commitment = Commitment(
                id: UUID(),
                text: commitmentText,
                source: analysis.source,
                recipient: analysis.involvedPeople.first ?? "Unknown",
                detectedDate: Date(),
                dueDate: analysis.suggestedDeadline,
                status: .pending,
                priority: analysis.urgencyLevel,
                context: String(originalContent.prefix(200)),
                originalContent: originalContent,
                confidence: analysis.confidence
            )
            
            activeCommitments.append(commitment)
            scheduleReminder(for: commitment)
        }
        
        savePersistedData()
    }
    
    func markCommitmentCompleted(_ commitmentId: UUID) {
        if let index = activeCommitments.firstIndex(where: { $0.id == commitmentId }) {
            activeCommitments[index].status = .completed
            activeCommitments[index].completedDate = Date()
            savePersistedData()
        }
    }
    
    func snoozeCommitment(_ commitmentId: UUID, until: Date) {
        if let index = activeCommitments.firstIndex(where: { $0.id == commitmentId }) {
            activeCommitments[index].status = .snoozed
            activeCommitments[index].dueDate = until
            scheduleReminder(for: activeCommitments[index])
            savePersistedData()
        }
    }
    
    // MARK: - Smart Reminders
    
    private func scheduleReminder(for commitment: Commitment) {
        let reminder = CommCommSmartReminder(
            id: UUID(),
            commitmentId: commitment.id,
            title: "Commitment Reminder",
            message: "Don't forget: \(commitment.text)",
            scheduledDate: calculateReminderDate(for: commitment),
            priority: commitment.priority,
            type: CommReminderType.commitment
        )
        
        pendingReminders.append(reminder)
        scheduleNotification(for: reminder)
    }
    
    private func calculateReminderDate(for commitment: Commitment) -> Date {
        let now = Date()
        
        if let dueDate = commitment.dueDate {
            // Remind based on urgency and due date
            let timeUntilDue = dueDate.timeIntervalSince(now)
            
            switch commitment.priority {
            case .urgent:
                return Date(timeIntervalSinceNow: min(timeUntilDue * 0.25, 1800)) // 25% of time or 30min max
            case .high:
                return Date(timeIntervalSinceNow: min(timeUntilDue * 0.5, 3600)) // 50% of time or 1hr max
            case .medium:
                return Date(timeIntervalSinceNow: min(timeUntilDue * 0.75, 7200)) // 75% of time or 2hr max
            case .low:
                return Date(timeIntervalSinceNow: min(timeUntilDue * 0.9, 14400)) // 90% of time or 4hr max
            }
        } else {
            // No specific due date, remind based on urgency
            switch commitment.priority {
            case .urgent:
                return Date(timeIntervalSinceNow: 1800) // 30 minutes
            case .high:
                return Date(timeIntervalSinceNow: 3600) // 1 hour
            case .medium:
                return Date(timeIntervalSinceNow: 10800) // 3 hours
            case .low:
                return Date(timeIntervalSinceNow: 21600) // 6 hours
            }
        }
    }
    
    private func scheduleNotification(for reminder: CommCommSmartReminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.message
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: reminder.scheduledDate.timeIntervalSinceNow,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to schedule notification: \(error.localizedDescription)")
            } else {
                self.logger.info("Scheduled reminder: \(reminder.title)")
            }
        }
    }
    
    private func startReminderEngine() {
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                self.checkOverdueCommitments()
                self.cleanupCompletedReminders()
            }
        }
    }
    
    private func checkOverdueCommitments() {
        let now = Date()
        
        for (index, commitment) in activeCommitments.enumerated() {
            if commitment.status == .pending,
               let dueDate = commitment.dueDate,
               dueDate < now {
                activeCommitments[index].status = .overdue
            }
        }
    }
    
    private func cleanupCompletedReminders() {
        let now = Date()
        pendingReminders.removeAll { reminder in
            reminder.scheduledDate < now
        }
    }
    
    // MARK: - Fallback Rule-Based Analysis
    
    private func analyzeEmailWithRules(_ content: String, sender: String?, subject: String?) -> CommunicationAnalysis? {
        let lowercased = content.lowercased()
        let questionMarks = content.filter { $0 == "?" }.count
        
        let requiresResponse = questionMarks > 0 ||
                              lowercased.contains("please") ||
                              lowercased.contains("can you") ||
                              lowercased.contains("could you") ||
                              lowercased.contains("let me know")
        
        let urgencyKeywords = ["urgent", "asap", "immediately", "deadline", "priority"]
        let isUrgent = urgencyKeywords.contains { lowercased.contains($0) }
        
        return CommunicationAnalysis(
            requiresResponse: requiresResponse,
            commitments: [],
            urgencyLevel: isUrgent ? .high : .medium,
            suggestedDeadline: nil,
            actionItems: questionMarks > 0 ? ["Respond to questions in email"] : [],
            involvedPeople: [sender].compactMap { $0 },
            confidence: 0.6,
            source: .email
        )
    }
    
    private func analyzeMessageWithRules(_ content: String, sender: String?, platform: String) -> CommunicationAnalysis? {
        let lowercased = content.lowercased()
        
        let requiresResponse = lowercased.contains("?") ||
                              lowercased.contains("@here") ||
                              lowercased.contains("@channel")
        
        return CommunicationAnalysis(
            requiresResponse: requiresResponse,
            commitments: [],
            urgencyLevel: .medium,
            suggestedDeadline: nil,
            actionItems: [],
            involvedPeople: [sender].compactMap { $0 },
            confidence: 0.5,
            source: platform == "slack" ? .slack : .teams
        )
    }
    
    private func analyzeMeetingWithRules(_ transcript: String, participants: [String]) -> [ActionItem] {
        let sentences = transcript.components(separatedBy: ".")
        var actionItems: [ActionItem] = []
        
        for sentence in sentences {
            let lowercased = sentence.lowercased()
            if lowercased.contains("action item") ||
               lowercased.contains("todo") ||
               lowercased.contains("follow up") ||
               lowercased.contains("will do") {
                
                actionItems.append(ActionItem(
                    id: UUID(),
                    text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    assignee: nil,
                    dueDate: nil,
                    priority: .medium,
                    status: .open,
                    sourceType: .meeting,
                    relatedMeeting: nil,
                    relatedCommitment: nil,
                    userModified: false,
                    createdDate: Date()
                ))
            }
        }
        
        return actionItems
    }
    
    // MARK: - Persistence
    
    private func savePersistedData() {
        let encoder = JSONEncoder()
        
        if let commitmentsData = try? encoder.encode(activeCommitments) {
            UserDefaults.standard.set(commitmentsData, forKey: "ActiveCommitments")
        }
        
        if let remindersData = try? encoder.encode(pendingReminders) {
            UserDefaults.standard.set(remindersData, forKey: "PendingReminders")
        }
    }
    
    private func loadPersistedData() {
        let decoder = JSONDecoder()
        
        if let commitmentsData = UserDefaults.standard.data(forKey: "ActiveCommitments"),
           let loadedCommitments = try? decoder.decode([Commitment].self, from: commitmentsData) {
            activeCommitments = loadedCommitments
        }
        
        if let remindersData = UserDefaults.standard.data(forKey: "PendingReminders"),
           let loadedReminders = try? decoder.decode([CommCommSmartReminder].self, from: remindersData) {
            pendingReminders = loadedReminders
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseDateString(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Fallback for natural language dates
        let now = Date()
        let lowercased = dateString.lowercased()
        
        if lowercased.contains("tomorrow") {
            return Calendar.current.date(byAdding: .day, value: 1, to: now)
        } else if lowercased.contains("next week") {
            return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)
        } else if lowercased.contains("friday") {
            return Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end
        }
        
        return nil
    }
}

// MARK: - Data Models

struct CommunicationAnalysis {
    let requiresResponse: Bool
    let commitments: [String]
    let urgencyLevel: Priority
    let suggestedDeadline: Date?
    let actionItems: [String]
    let involvedPeople: [String]
    let confidence: Double
    let source: CommitmentSource
}

struct Commitment: Codable, Identifiable {
    let id: UUID
    let text: String
    let source: CommitmentSource
    let recipient: String
    let detectedDate: Date
    var dueDate: Date?
    var status: CommitmentStatus
    let priority: Priority
    let context: String
    let originalContent: String
    let confidence: Double
    var completedDate: Date?
}

enum CommitmentStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case overdue = "overdue"
    case dismissed = "dismissed"
    case snoozed = "snoozed"
}

struct ActionItem: Codable, Identifiable {
    let id: UUID
    let text: String
    let assignee: String?
    let dueDate: Date?
    let priority: Priority
    var status: ActionItemStatus
    let sourceType: ActionItemSource
    let relatedMeeting: UUID? // Meeting session ID
    let relatedCommitment: UUID? // Commitment ID
    var userModified: Bool
    let createdDate: Date
}

enum ActionItemStatus: String, Codable, CaseIterable {
    case open = "open"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
}

enum ActionItemSource: String, Codable, CaseIterable {
    case meeting = "meeting"
    case email = "email"
    case message = "message"
    case manual = "manual"
}

struct CommCommSmartReminder: Codable, Identifiable {
    let id: UUID
    let commitmentId: UUID
    let title: String
    let message: String
    let scheduledDate: Date
    let priority: Priority
    let type: CommReminderType
}

enum CommReminderType: String, Codable, CaseIterable {
    case commitment = "commitment"
    case followUp = "follow_up"
    case deadline = "deadline"
    case meeting = "meeting"
}

struct EmailThread: Codable, Identifiable {
    let id: UUID
    let subject: String
    let participants: [String]
    let lastMessage: Date
    let responseRequired: Bool
    var lastResponseDate: Date?
    let urgency: Priority
    let threadContext: String
    var reminderScheduled: Date?
}

// MARK: - Foundation Models Data Structures

#if canImport(FoundationModels)
@Generable
struct EmailAnalysisResult: Codable {
    @Guide(description: "Whether this email requires a response from the recipient")
    let requiresResponse: Bool
    
    @Guide(description: "List of commitments or promises made in the email")
    let commitments: [String]
    
    @Guide(description: "Urgency level: 1=low, 2=medium, 3=high, 4=urgent")
    let urgencyLevel: Int
    
    @Guide(description: "Suggested deadline for response (ISO8601 format or natural language)")
    let suggestedDeadline: String?
    
    @Guide(description: "Key action items or questions that need attention")
    let actionItems: [String]
    
    @Guide(description: "People mentioned who might need follow-up")
    let involvedPeople: [String]
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}

@Generable
struct MessageAnalysisResult: Codable {
    @Guide(description: "Whether this message requires a response")
    let requiresResponse: Bool
    
    @Guide(description: "List of commitments or requests made")
    let commitments: [String]
    
    @Guide(description: "Urgency level: 1=low, 2=medium, 3=high, 4=urgent")
    let urgencyLevel: Int
    
    @Guide(description: "Suggested response timeframe (e.g., 'within 1 hour', 'by end of day')")
    let suggestedTimeframe: String?
    
    @Guide(description: "Key action items extracted from the message")
    let actionItems: [String]
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}

@Generable
struct MeetingAnalysisResult: Codable {
    @Guide(description: "List of action items extracted from the meeting")
    let actionItems: [MeetingActionItem]
}

@Generable
struct MeetingActionItem: Codable {
    @Guide(description: "Description of the action item")
    let text: String
    
    @Guide(description: "Person assigned to the action item")
    let assignee: String?
    
    @Guide(description: "Due date for the action item (ISO8601 format or natural language)")
    let dueDate: String?
    
    @Guide(description: "Priority level: 1=low, 2=medium, 3=high, 4=urgent")
    let priority: Int
}
#endif