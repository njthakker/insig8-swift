import Foundation
import SwiftUI
import Combine
import OSLog

// MARK: - AI Task Manager
@MainActor
class AITaskManager: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "TaskManager")
    
    @Published var activeTasks: [AITask] = []
    @Published var completedTasks: [AITask] = []
    @Published var snoozedTasks: [AITask] = []
    
    // Task filtering and search
    @Published var taskFilters: [ContentTag] = []
    @Published var searchQuery: String = ""
    
    private let maxActiveTasks = 100
    private let maxCompletedTasks = 200
    
    init() {
        _ = loadPersistedTasks()
        startTaskMonitoring()
    }
    
    // MARK: - Task Management
    
    func addTask(_ task: AITask) {
        // Avoid duplicates
        if !activeTasks.contains(where: { $0.id == task.id }) {
            activeTasks.append(task)
            sortActiveTasks()
            
            // Limit active tasks
            if activeTasks.count > maxActiveTasks {
                let overdueTask = activeTasks.removeFirst()
                completedTasks.append(overdueTask)
            }
            
            savePersistedTasks()
            logger.info("Added task: \(task.description)")
        }
    }
    
    func updateTask(_ taskId: UUID, updates: [String: Any]) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            activeTasks[index].applyUpdates(updates)
            activeTasks[index].modifiedDate = Date()
            sortActiveTasks()
            savePersistedTasks()
            logger.info("Updated task: \(taskId)")
        }
    }
    
    func completeTask(_ taskId: UUID) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            var completedTask = activeTasks.remove(at: index)
            completedTask.status = .completed
            completedTask.modifiedDate = Date()
            
            completedTasks.append(completedTask)
            
            // Limit completed tasks
            if completedTasks.count > maxCompletedTasks {
                completedTasks.removeFirst()
            }
            
            savePersistedTasks()
            logger.info("Completed task: \(taskId)")
        }
    }
    
    func dismissTask(_ taskId: UUID) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            var dismissedTask = activeTasks.remove(at: index)
            dismissedTask.status = .dismissed
            dismissedTask.modifiedDate = Date()
            
            completedTasks.append(dismissedTask)
            savePersistedTasks()
            logger.info("Dismissed task: \(taskId)")
        }
    }
    
    func snoozeTask(_ taskId: UUID, until: Date) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            var snoozedTask = activeTasks.remove(at: index)
            snoozedTask.status = .snoozed
            snoozedTask.dueDate = until
            snoozedTask.modifiedDate = Date()
            
            snoozedTasks.append(snoozedTask)
            savePersistedTasks()
            logger.info("Snoozed task \(taskId) until \(until)")
        }
    }
    
    func modifyTask(_ taskId: UUID, modification: TaskModification) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            switch modification {
            case .changeDueDate(let newDate):
                activeTasks[index].dueDate = newDate
            case .changePriority(let newPriority):
                activeTasks[index].priority = newPriority
            case .changeDescription(let newDescription):
                activeTasks[index].description = newDescription
            case .markCompleted:
                completeTask(taskId)
                return
            case .markInProgress:
                activeTasks[index].status = .in_progress
            }
            
            activeTasks[index].modifiedDate = Date()
            activeTasks[index].userModified = true
            sortActiveTasks()
            savePersistedTasks()
        }
    }
    
    // MARK: - Task Retrieval and Search
    
    func getActiveTasks() -> [AITask] {
        return activeTasks
    }
    
    func getFilteredTasks() -> [AITask] {
        var filtered = activeTasks
        
        // Apply tag filters
        if !taskFilters.isEmpty {
            filtered = filtered.filter { task in
                !Set(task.tags).intersection(Set(taskFilters)).isEmpty
            }
        }
        
        // Apply search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            filtered = filtered.filter { task in
                task.description.lowercased().contains(query) ||
                task.tags.contains { $0.rawValue.lowercased().contains(query) }
            }
        }
        
        return filtered
    }
    
    func searchTasks(query: String) -> [AITask] {
        let lowercasedQuery = query.lowercased()
        let allTasks = activeTasks + snoozedTasks + completedTasks
        
        let matchingTasks = allTasks.filter { task in
            task.description.lowercased().contains(lowercasedQuery) ||
            task.tags.contains { $0.rawValue.lowercased().contains(lowercasedQuery) } ||
            getSourceDescription(task.source).lowercased().contains(lowercasedQuery)
        }
        
        // Calculate relevance scores
        return matchingTasks.map { task in
            var updatedTask = task
            updatedTask.relevanceScore = calculateRelevanceScore(for: task, query: lowercasedQuery)
            return updatedTask
        }.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    func getTasksByTag(_ tag: ContentTag) -> [AITask] {
        return activeTasks.filter { $0.tags.contains(tag) }
    }
    
    func getTasksByPriority(_ priority: ProcessingPriority) -> [AITask] {
        return activeTasks.filter { $0.priority == priority }
    }
    
    func getOverdueTasks() -> [AITask] {
        let now = Date()
        return activeTasks.filter { task in
            if let dueDate = task.dueDate {
                return dueDate < now && task.status != .completed
            }
            return false
        }
    }
    
    func getUpcomingTasks(within hours: Int = 24) -> [AITask] {
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .hour, value: hours, to: now) ?? now
        
        return activeTasks.filter { task in
            if let dueDate = task.dueDate {
                return dueDate > now && dueDate <= futureDate
            }
            return false
        }
    }
    
    // MARK: - Task Statistics
    
    func getTaskStatistics() -> TaskStatistics {
        let overdue = getOverdueTasks().count
        let upcoming = getUpcomingTasks().count
        let urgent = getTasksByPriority(.urgent).count
        let high = getTasksByPriority(.high).count
        
        var tagCounts: [ContentTag: Int] = [:]
        for task in activeTasks {
            for tag in task.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        
        return TaskStatistics(
            totalActive: activeTasks.count,
            totalCompleted: completedTasks.count,
            totalSnoozed: snoozedTasks.count,
            overdue: overdue,
            upcoming: upcoming,
            urgent: urgent,
            high: high,
            tagDistribution: tagCounts
        )
    }
    
    // MARK: - Background Monitoring
    
    private func startTaskMonitoring() {
        // Check tasks every 15 minutes
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            Task { @MainActor in
                self.processOverdueTasks()
                self.processSnoozedTasks()
                self.cleanupOldTasks()
            }
        }
    }
    
    private func processOverdueTasks() {
        let now = Date()
        
        for (index, task) in activeTasks.enumerated() {
            if let dueDate = task.dueDate, dueDate < now && task.status == .pending {
                activeTasks[index].status = .in_progress // Mark as needing attention
                logger.warning("Task became overdue: \(task.id)")
            }
        }
    }
    
    private func processSnoozedTasks() {
        let now = Date()
        var tasksToReactivate: [AITask] = []
        
        for (index, task) in snoozedTasks.enumerated().reversed() {
            if let dueDate = task.dueDate, dueDate <= now {
                var reactivatedTask = snoozedTasks.remove(at: index)
                reactivatedTask.status = .pending
                tasksToReactivate.append(reactivatedTask)
            }
        }
        
        activeTasks.append(contentsOf: tasksToReactivate)
        
        if !tasksToReactivate.isEmpty {
            sortActiveTasks()
            savePersistedTasks()
            logger.info("Reactivated \(tasksToReactivate.count) snoozed tasks")
        }
    }
    
    private func cleanupOldTasks() {
        // Remove very old completed tasks (older than 30 days)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let originalCount = completedTasks.count
        completedTasks = completedTasks.filter { $0.modifiedDate > thirtyDaysAgo }
        
        if completedTasks.count < originalCount {
            logger.info("Cleaned up \(originalCount - self.completedTasks.count) old completed tasks")
            savePersistedTasks()
        }
    }
    
    // MARK: - Utility Methods
    
    private func sortActiveTasks() {
        activeTasks.sort { task1, task2 in
            // Sort by priority first
            if task1.priority != task2.priority {
                return task1.priority.rawValue > task2.priority.rawValue
            }
            
            // Then by due date (closest first)
            switch (task1.dueDate, task2.dueDate) {
            case (let date1?, let date2?):
                return date1 < date2
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return task1.createdDate > task2.createdDate
            }
        }
    }
    
    private func calculateRelevanceScore(for task: AITask, query: String) -> Float {
        var score: Float = 0.0
        
        // Description match
        if task.description.lowercased().contains(query) {
            score += 0.6
        }
        
        // Tag match
        for tag in task.tags {
            if tag.rawValue.lowercased().contains(query) {
                score += 0.3
            }
        }
        
        // Source match
        if getSourceDescription(task.source).lowercased().contains(query) {
            score += 0.2
        }
        
        // Boost recent tasks
        let daysSinceCreation = Date().timeIntervalSince(task.createdDate) / (24 * 3600)
        if daysSinceCreation < 1 {
            score += 0.1
        }
        
        // Boost high priority tasks
        score += Float(task.priority.rawValue) * 0.05
        
        return min(score, 1.0)
    }
    
    private func getSourceDescription(_ source: ContentSource) -> String {
        switch source {
        case .email(let sender, let subject):
            return "Email from \(sender ?? "unknown"): \(subject ?? "")"
        case .screenCapture(let app):
            return "Screen capture from \(app)"
        case .meeting(let participants):
            return "Meeting with \(participants.joined(separator: ", "))"
        case .clipboard:
            return "Clipboard content"
        case .browser(let url, let title):
            return "Browser: \(title ?? url)"
        case .manual:
            return "Manual entry"
        }
    }
    
    // MARK: - Persistence
    
    func savePersistedTasks() {
        let encoder = JSONEncoder()
        
        if let activeData = try? encoder.encode(activeTasks) {
            UserDefaults.standard.set(activeData, forKey: "ActiveTasks")
        }
        
        if let completedData = try? encoder.encode(completedTasks) {
            UserDefaults.standard.set(completedData, forKey: "CompletedTasks")
        }
        
        if let snoozedData = try? encoder.encode(snoozedTasks) {
            UserDefaults.standard.set(snoozedData, forKey: "SnoozedTasks")
        }
    }
    
    func loadPersistedTasks() -> [AITask] {
        let decoder = JSONDecoder()
        
        if let activeData = UserDefaults.standard.data(forKey: "ActiveTasks"),
           let loadedActive = try? decoder.decode([AITask].self, from: activeData) {
            activeTasks = loadedActive
        }
        
        if let completedData = UserDefaults.standard.data(forKey: "CompletedTasks"),
           let loadedCompleted = try? decoder.decode([AITask].self, from: completedData) {
            completedTasks = loadedCompleted
        }
        
        if let snoozedData = UserDefaults.standard.data(forKey: "SnoozedTasks"),
           let loadedSnoozed = try? decoder.decode([AITask].self, from: snoozedData) {
            snoozedTasks = loadedSnoozed
        }
        
        sortActiveTasks()
        logger.info("Loaded persisted tasks: \(self.activeTasks.count) active, \(self.completedTasks.count) completed, \(self.snoozedTasks.count) snoozed")
        
        return activeTasks
    }
    
    // MARK: - Public Interface Methods
    
    func setTaskFilters(_ filters: [ContentTag]) {
        taskFilters = filters
    }
    
    func setSearchQuery(_ query: String) {
        searchQuery = query
    }
    
    func clearFilters() {
        taskFilters.removeAll()
        searchQuery = ""
    }
}

// MARK: - Supporting Data Structures

struct TaskStatistics {
    let totalActive: Int
    let totalCompleted: Int
    let totalSnoozed: Int
    let overdue: Int
    let upcoming: Int
    let urgent: Int
    let high: Int
    let tagDistribution: [ContentTag: Int]
}