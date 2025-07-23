import Foundation
import OSLog
import UserNotifications

// MARK: - Smart Reminder Agent
class SmartReminderAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "ReminderAgent")
    weak var delegate: AIAgentDelegate?
    
    // Active reminders tracking
    private var activeReminders: [UUID: SmartReminderTask] = [:]
    
    init() {
        setupNotificationHandling()
        startReminderMonitoring()
    }
    
    private func setupNotificationHandling() {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                self.logger.info("Notification permissions granted")
            } else {
                self.logger.warning("Notification permissions denied")
            }
        }
    }
    
    func createUrgentReminder(_ item: ProcessingItem, tags: [ContentTag]) async {
        logger.info("Creating urgent reminder for: \(item.source)")
        
        let reminderTask = SmartReminderTask(
            id: UUID(),
            originalItemId: item.id,
            content: item.content,
            source: item.source,
            tags: tags,
            urgencyLevel: .urgent,
            reminderTime: Date().addingTimeInterval(300), // 5 minutes for urgent
            createdAt: Date(),
            status: .pending
        )
        
        activeReminders[reminderTask.id] = reminderTask
        
        // Schedule immediate notification
        await scheduleNotification(for: reminderTask)
        
        // Create AI task
        let aiTask = AITask(
            id: reminderTask.id,
            description: "URGENT: \(generateReminderDescription(for: reminderTask))",
            source: item.source,
            tags: [.urgent_action, .reminder] + tags,
            priority: .urgent,
            status: .pending,
            dueDate: reminderTask.reminderTime,
            createdDate: Date(),
            modifiedDate: Date(),
            relevanceScore: 1.0
        )
        
        delegate?.agentDidCreateTask(aiTask)
    }
    
    func createTimedReminder(_ item: ProcessingItem, tags: [ContentTag], reminderTime: Date) async {
        logger.info("Creating timed reminder for: \(item.source)")
        
        let reminderTask = SmartReminderTask(
            id: UUID(),
            originalItemId: item.id,
            content: item.content,
            source: item.source,
            tags: tags,
            urgencyLevel: determineUrgencyLevel(from: tags),
            reminderTime: reminderTime,
            createdAt: Date(),
            status: .pending
        )
        
        activeReminders[reminderTask.id] = reminderTask
        
        // Schedule notification
        await scheduleNotification(for: reminderTask)
        
        // Create AI task
        let aiTask = AITask(
            id: reminderTask.id,
            description: generateReminderDescription(for: reminderTask),
            source: item.source,
            tags: [.reminder] + tags,
            priority: reminderTask.urgencyLevel,
            status: .pending,
            dueDate: reminderTime,
            createdDate: Date(),
            modifiedDate: Date(),
            relevanceScore: 0.8
        )
        
        delegate?.agentDidCreateTask(aiTask)
    }
    
    func createFollowupReminder(for commitment: String, recipient: String, originalSource: ContentSource, followupTime: Date) async {
        logger.info("Creating followup reminder for commitment to: \(recipient)")
        
        let reminderTask = SmartReminderTask(
            id: UUID(),
            originalItemId: UUID(), // New ID for followup
            content: "Follow up on commitment: \(commitment)",
            source: originalSource,
            tags: [.commitment, .followup_required],
            urgencyLevel: .high,
            reminderTime: followupTime,
            createdAt: Date(),
            status: .pending
        )
        
        activeReminders[reminderTask.id] = reminderTask
        
        // Schedule notification
        await scheduleNotification(for: reminderTask)
        
        // Create AI task
        let aiTask = AITask(
            id: reminderTask.id,
            description: "Follow up with \(recipient): \(commitment)",
            source: originalSource,
            tags: [.commitment, .followup_required, .reminder],
            priority: .high,
            status: .pending,
            dueDate: followupTime,
            createdDate: Date(),
            modifiedDate: Date(),
            relevanceScore: 0.9
        )
        
        delegate?.agentDidCreateTask(aiTask)
    }
    
    private func scheduleNotification(for reminder: SmartReminderTask) async {
        let content = UNMutableNotificationContent()
        content.title = getReminderTitle(for: reminder)
        content.body = reminder.content.count > 100 ? String(reminder.content.prefix(97)) + "..." : reminder.content
        content.sound = reminder.urgencyLevel == .urgent ? .defaultCritical : .default
        content.categoryIdentifier = "REMINDER_CATEGORY"
        
        // Add action buttons
        content.userInfo = [
            "reminderId": reminder.id.uuidString,
            "urgencyLevel": reminder.urgencyLevel.rawValue
        ]
        
        let timeInterval = reminder.reminderTime.timeIntervalSinceNow
        
        if timeInterval > 0 {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: reminder.id.uuidString,
                content: content,
                trigger: trigger
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                logger.info("Scheduled notification for reminder: \(reminder.id)")
            } catch {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        } else {
            // Immediate notification
            let request = UNNotificationRequest(
                identifier: reminder.id.uuidString,
                content: content,
                trigger: nil
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                logger.info("Sent immediate notification for reminder: \(reminder.id)")
            } catch {
                logger.error("Failed to send immediate notification: \(error.localizedDescription)")
            }
        }
    }
    
    private func startReminderMonitoring() {
        // Check reminders every 10 minutes
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task {
                await self.processOverdueReminders()
                await self.cleanupCompletedReminders()
            }
        }
    }
    
    private func processOverdueReminders() async {
        let now = Date()
        
        for (_, reminder) in activeReminders {
            if reminder.status == .pending && now > reminder.reminderTime.addingTimeInterval(3600) { // 1 hour overdue
                // Create escalated reminder
                let escalatedTask = AITask(
                    id: UUID(),
                    description: "OVERDUE REMINDER: \(generateReminderDescription(for: reminder))",
                    source: reminder.source,
                    tags: [.urgent_action, .reminder] + reminder.tags,
                    priority: .urgent,
                    status: .pending,
                    dueDate: now,
                    createdDate: now,
                    modifiedDate: now,
                    relevanceScore: 1.0
                )
                
                delegate?.agentDidCreateTask(escalatedTask)
                
                // Mark original as escalated
                activeReminders[reminder.id]?.status = .escalated
                
                logger.warning("Escalated overdue reminder: \(reminder.id)")
            }
        }
    }
    
    private func cleanupCompletedReminders() {
        let completedIds = activeReminders.compactMap { (id, reminder) in
            reminder.status == .completed || reminder.status == .dismissed ? id : nil
        }
        
        for id in completedIds {
            activeReminders.removeValue(forKey: id)
            
            // Cancel notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        }
        
        if !completedIds.isEmpty {
            logger.info("Cleaned up \(completedIds.count) completed reminders")
        }
    }
    
    // MARK: - Public Methods
    
    func completeReminder(_ reminderId: UUID) {
        if activeReminders[reminderId] != nil {
            activeReminders[reminderId]?.status = .completed
            logger.info("Completed reminder: \(reminderId)")
        }
    }
    
    func dismissReminder(_ reminderId: UUID) {
        if activeReminders[reminderId] != nil {
            activeReminders[reminderId]?.status = .dismissed
            logger.info("Dismissed reminder: \(reminderId)")
        }
    }
    
    func snoozeReminder(_ reminderId: UUID, until: Date) async {
        if var reminder = activeReminders[reminderId] {
            reminder.reminderTime = until
            reminder.status = .snoozed
            activeReminders[reminderId] = reminder
            
            // Reschedule notification
            await scheduleNotification(for: reminder)
            
            logger.info("Snoozed reminder \(reminderId) until \(until)")
        }
    }
    
    func getActiveReminders() -> [SmartReminderTask] {
        return Array(activeReminders.values.filter { $0.status == .pending || $0.status == .snoozed })
    }
    
    // MARK: - Helper Methods
    
    private func determineUrgencyLevel(from tags: [ContentTag]) -> ProcessingPriority {
        if tags.contains(.urgent_action) {
            return .urgent
        } else if tags.contains(.important) || tags.contains(.deadline) {
            return .high
        } else if tags.contains(.commitment) || tags.contains(.followup_required) {
            return .medium
        } else {
            return .low
        }
    }
    
    private func generateReminderDescription(for reminder: SmartReminderTask) -> String {
        switch reminder.source {
        case .email(let sender, let subject):
            return "Email reminder: \(subject ?? "No subject") from \(sender ?? "Unknown")"
        case .screenCapture(let app):
            return "Message reminder from \(app): \(String(reminder.content.prefix(50)))"
        case .meeting(let participants):
            return "Meeting followup with \(participants.joined(separator: ", "))"
        case .clipboard:
            return "Clipboard reminder: \(String(reminder.content.prefix(50)))"
        case .browser(_, let title):
            return "Browser reminder: \(title ?? "Unknown page")"
        case .manual:
            return "Manual reminder: \(String(reminder.content.prefix(50)))"
        }
    }
    
    private func getReminderTitle(for reminder: SmartReminderTask) -> String {
        switch reminder.urgencyLevel {
        case .urgent:
            return "🚨 Urgent Reminder"
        case .high:
            return "⚠️ Important Reminder"
        case .medium:
            return "💭 Reminder"
        case .low:
            return "📝 Note"
        }
    }
}

// MARK: - Supporting Data Structures

struct SmartReminderTask {
    let id: UUID
    let originalItemId: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let urgencyLevel: ProcessingPriority
    var reminderTime: Date
    let createdAt: Date
    var status: ReminderStatus
}

enum ReminderStatus: String, Codable {
    case pending = "pending"
    case snoozed = "snoozed"
    case completed = "completed"
    case dismissed = "dismissed"
    case escalated = "escalated"
}