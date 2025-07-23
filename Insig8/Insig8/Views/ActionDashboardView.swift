//
//  ActionDashboardView.swift
//  Insig8
//
//  Default command palette view showing actions, follow-ups, and AI status
//

import SwiftUI

struct ActionDashboardView: View {
    @EnvironmentObject var appStore: AppStore
    @StateObject private var actionManager = ActionManager(
        sqliteDB: AppStore.shared.sqliteVectorDB,
        secureStorage: AppStore.shared.secureStorage
    )
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // AI Status Header
                AIStatusHeader()
                
                // Quick Actions Section
                if !actionManager.urgentActions.isEmpty {
                    UrgentActionsSection(actions: actionManager.urgentActions)
                }
                
                // Active Actions Section
                ActiveActionsSection(actions: actionManager.activeActions)
                
                // Upcoming Reminders Section
                UpcomingRemindersSection(followups: actionManager.pendingFollowups)
                
                // Recent Activity Section
                RecentActivitySection()
                
                // Quick Commands Section
                QuickCommandsSection()
            }
            .padding()
        }
        .environmentObject(actionManager)
    }
}

struct AIStatusHeader: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AI Assistant")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // AI Status Indicator
                    AIStatusIndicatorDot()
                }
                
                Text(getCurrentTimeGreeting())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Quick stats
            HStack(spacing: 16) {
                StatBadge(
                    value: "\(appStore.getActiveTasks().count)",
                    label: "Active",
                    color: .blue
                )
                
                StatBadge(
                    value: "\(appStore.getPipelineStatistics().totalItemsProcessed)",
                    label: "Processed",
                    color: .green
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func getCurrentTimeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 0..<12:
            return "Good morning! Ready to tackle the day?"
        case 12..<17:
            return "Good afternoon! How can I help?"
        default:
            return "Good evening! Wrapping up the day?"
        }
    }
}

struct AIStatusIndicatorDot: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appStore.aiService.isAIAvailable ? .green : .red)
                .frame(width: 8, height: 8)
            
            Text(appStore.aiService.isAIAvailable ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct UrgentActionsSection: View {
    let actions: [Action]
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Urgent Actions",
                subtitle: "\(actions.count) requiring immediate attention",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
            
            VStack(spacing: 8) {
                ForEach(actions.prefix(3)) { action in
                    UrgentActionCard(action: action)
                }
                
                if actions.count > 3 {
                    Button("View All \(actions.count) Urgent Actions") {
                        // Search for urgent actions
                        appStore.searchQuery = "urgent actions"
                        appStore.performFullSearchOnEnter("urgent actions")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

struct UrgentActionCard: View {
    let action: Action
    @EnvironmentObject var actionManager: ActionManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Priority indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(.red)
                .frame(width: 4, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(action.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    Text(timeAgoString(from: action.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if !action.description.isEmpty {
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Context info
                if let context = action.context {
                    HStack(spacing: 4) {
                        Image(systemName: iconForSource(action.source))
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        
                        Text(context.appName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let contact = context.contactName {
                            Text("• \(contact)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Quick actions
            VStack(spacing: 4) {
                Button {
                    // Mark as completed
                    actionManager.markActionCompleted(
                        actionId: action.id,
                        responseText: "Marked as completed from dashboard",
                        detectedAt: Date()
                    )
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.green)
                
                Button {
                    // Snooze for 1 hour
                    actionManager.modifyAction(action.id, modification: .snooze(3600))
                } label: {
                    Image(systemName: "clock")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.orange)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ActiveActionsSection: View {
    let actions: [Action]
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Active Actions",
                subtitle: "\(actions.count) pending items",
                icon: "list.bullet.circle.fill",
                color: .blue
            )
            
            if actions.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "All caught up!",
                    subtitle: "No pending actions right now"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(actions.prefix(5)) { action in
                        ActionCard(action: action)
                    }
                    
                    if actions.count > 5 {
                        Button("View All \(actions.count) Actions") {
                            // Search for all actions
                            appStore.searchQuery = "all actions"
                            appStore.performFullSearchOnEnter("all actions")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

struct ActionCard: View {
    let action: Action
    @EnvironmentObject var actionManager: ActionManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type indicator
            ActionTypeIndicator(type: action.type, priority: action.priority)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(action.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    DueDateIndicator(dueDate: action.dueDate)
                }
                
                if !action.description.isEmpty {
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Context info
                if let context = action.context {
                    HStack(spacing: 4) {
                        Image(systemName: iconForSource(action.source))
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        
                        Text(context.appName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let contact = context.contactName {
                            Text("• \(contact)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Quick action menu
            Menu {
                Button("Mark Complete") {
                    actionManager.markActionCompleted(
                        actionId: action.id,
                        responseText: "Completed from dashboard",
                        detectedAt: Date()
                    )
                }
                
                Button("Snooze 1 Hour") {
                    actionManager.modifyAction(action.id, modification: .snooze(3600))
                }
                
                Button("Snooze Until Tomorrow") {
                    actionManager.modifyAction(action.id, modification: .snooze(86400))
                }
                
                Divider()
                
                Button("Dismiss", role: .destructive) {
                    actionManager.modifyAction(action.id, modification: .dismiss)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ActionTypeIndicator: View {
    let type: ActionType
    let priority: Priority
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconForActionType(type))
                .font(.subheadline)
                .foregroundColor(colorForPriority(priority))
            
            Circle()
                .fill(colorForPriority(priority))
                .frame(width: 4, height: 4)
        }
        .frame(width: 20)
    }
    
    private func iconForActionType(_ type: ActionType) -> String {
        switch type {
        case .response:
            return "arrowshape.turn.up.left"
        case .commitment:
            return "handshake"
        case .task:
            return "checkmark.square"
        case .followup:
            return "clock.arrow.circlepath"
        }
    }
    
    private func colorForPriority(_ priority: Priority) -> Color {
        switch priority {
        case .urgent:
            return .red
        case .high:
            return .orange
        case .medium:
            return .blue
        case .low:
            return .gray
        }
    }
}

struct DueDateIndicator: View {
    let dueDate: Date
    
    var body: some View {
        let timeUntilDue = dueDate.timeIntervalSince(Date())
        let isOverdue = timeUntilDue < 0
        
        HStack(spacing: 4) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "clock")
                .font(.caption2)
                .foregroundColor(isOverdue ? .red : .secondary)
            
            Text(dueDateString(from: dueDate))
                .font(.caption2)
                .foregroundColor(isOverdue ? .red : .secondary)
        }
    }
    
    private func dueDateString(from date: Date) -> String {
        let timeInterval = date.timeIntervalSince(Date())
        
        if timeInterval < 0 {
            return "Overdue"
        } else if timeInterval < 3600 {
            return "\(Int(timeInterval / 60))m"
        } else if timeInterval < 86400 {
            return "\(Int(timeInterval / 3600))h"
        } else {
            return "\(Int(timeInterval / 86400))d"
        }
    }
}

struct UpcomingRemindersSection: View {
    let followups: [Followup]
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Upcoming Reminders",
                subtitle: "\(followups.count) scheduled",
                icon: "bell.fill",
                color: .orange
            )
            
            if followups.isEmpty {
                EmptyStateView(
                    icon: "bell.slash",
                    title: "No reminders",
                    subtitle: "All follow-ups are up to date"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(followups.prefix(3)) { followup in
                        FollowupCard(followup: followup)
                    }
                    
                    if followups.count > 3 {
                        Button("View All \(followups.count) Reminders") {
                            // Search for all reminders
                            appStore.searchQuery = "reminders"
                            appStore.performFullSearchOnEnter("reminders")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

struct FollowupCard: View {
    let followup: Followup
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForFollowupType(followup.type))
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(followup.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(followup.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text("With: \(followup.recipient)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Due: \(dateString(from: followup.dueDate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func iconForFollowupType(_ type: ActionFollowupType) -> String {
        switch type {
        case .emailFollowup:
            return "envelope"
        case .messageFollowup:
            return "message"
        case .meetingFollowup:
            return "video"
        }
    }
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct RecentActivitySection: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Recent Activity",
                subtitle: "Latest AI processing",
                icon: "clock.fill",
                color: .green
            )
            
            VStack(spacing: 8) {
                RecentActivityItem(
                    icon: "camera.viewfinder",
                    title: "Screen content analyzed",
                    subtitle: "Slack - 2 minutes ago",
                    color: .blue
                )
                
                RecentActivityItem(
                    icon: "envelope",
                    title: "Email processed",
                    subtitle: "New action item created",
                    color: .green
                )
                
                RecentActivityItem(
                    icon: "brain.head.profile",
                    title: "AI suggestion generated",
                    subtitle: "Follow up with client",
                    color: .purple
                )
            }
        }
    }
}

struct RecentActivityItem: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct QuickCommandsSection: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var actionManager: ActionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Quick Commands",
                subtitle: "Common actions",
                icon: "command",
                color: .gray
            )
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                QuickCommandButton(
                    icon: "plus.circle",
                    title: "Add Task",
                    subtitle: "Create new action"
                ) {
                    // Create a new manual task
                    let newAction = Action(
                        id: UUID(),
                        type: .task,
                        title: "New Task",
                        description: "Manually created task",
                        source: .manual,
                        priority: .medium,
                        createdAt: Date(),
                        dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                        status: .active,
                        completedAt: nil,
                        responseText: nil,
                        context: nil
                    )
                    actionManager.addAction(newAction)
                }
                
                QuickCommandButton(
                    icon: "calendar.badge.plus",
                    title: "Schedule",
                    subtitle: "Calendar events"
                ) {
                    // Switch to calendar widget
                    appStore.switchToWidget(.calendar)
                }
                
                QuickCommandButton(
                    icon: "doc.on.clipboard",
                    title: "Clipboard",
                    subtitle: "View history"
                ) {
                    // Switch to clipboard widget
                    appStore.switchToWidget(.clipboard)
                }
                
                QuickCommandButton(
                    icon: "gear",
                    title: "Settings",
                    subtitle: "Configure AI"
                ) {
                    // Switch to settings widget
                    appStore.switchToWidget(.settings)
                }
                
                QuickCommandButton(
                    icon: "brain.head.profile",
                    title: "AI Monitor",
                    subtitle: "View processing"
                ) {
                    // Switch to AI monitor widget
                    appStore.switchToWidget(.aiMonitor)
                }
            }
        }
    }
}

struct QuickCommandButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Helper Functions

private func timeAgoString(from date: Date) -> String {
    let timeInterval = Date().timeIntervalSince(date)
    
    if timeInterval < 60 {
        return "now"
    } else if timeInterval < 3600 {
        return "\(Int(timeInterval / 60))m ago"
    } else if timeInterval < 86400 {
        return "\(Int(timeInterval / 3600))h ago"
    } else {
        return "\(Int(timeInterval / 86400))d ago"
    }
}

private func iconForSource(_ source: ActionSource) -> String {
    switch source {
    case .screenCapture:
        return "camera.viewfinder"
    case .email:
        return "envelope"
    case .meeting:
        return "video"
    case .followup:
        return "clock.arrow.circlepath"
    case .manual:
        return "pencil"
    }
}

#Preview {
    ActionDashboardView()
        .environmentObject(AppStore.shared)
        .frame(width: 600, height: 800)
}