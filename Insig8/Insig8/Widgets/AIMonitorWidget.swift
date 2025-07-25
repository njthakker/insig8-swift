//
//  AIMonitorWidget.swift
//  Insig8
//
//  AI Processing Monitor - Real-time view of AI pipeline processing
//  Shows filtered content and AI output without burdening on-device LLM
//

import SwiftUI
import Combine

struct AIMonitorWidget: View {
    @EnvironmentObject var appStore: AppStore
    @State private var processingItems: [ProcessingItem] = []
    @State private var recentProcessedItems: [ProcessedItem] = []
    @State private var isExpanded = false
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            AIMonitorHeader(
                isExpanded: $isExpanded,
                selectedTab: $selectedTab,
                stats: appStore.getPipelineStatistics()
            )
            
            Divider()
            
            // Content based on selected tab
            TabView(selection: $selectedTab) {
                // Live Processing Tab
                LiveProcessingView(
                    processingItems: processingItems,
                    isExpanded: isExpanded
                )
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("Live Processing")
                }
                .tag(0)
                
                // Recent Results Tab
                RecentResultsView(
                    recentItems: recentProcessedItems,
                    isExpanded: isExpanded
                )
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Recent Results")
                }
                .tag(1)
                
                // Pipeline Stats Tab
                PipelineStatsView(
                    stats: appStore.getPipelineStatistics(),
                    agentStatus: {
                        #if !MEETING_ONLY
                        return appStore.aiPipeline.getAgentStatus()
                        #else
                        return []
                        #endif
                    }()
                )
                .tabItem {
                    Image(systemName: "chart.bar")
                    Text("Statistics")
                }
                .tag(2)
            }
            .tabViewStyle(DefaultTabViewStyle())
        }
        .onAppear {
            startMonitoring()
        }
    }
    
    private func startMonitoring() {
        // Monitor AI pipeline processing items
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                // Get current processing items (without calling LLM)
                #if !MEETING_ONLY
                self.processingItems = appStore.aiPipeline.getPendingItems()
                #else
                self.processingItems = []
                #endif
                
                // Update recent processed items (simulated for now)
                // In production, this would come from the AI pipeline's processed items queue
                updateRecentItems()
            }
        }
    }
    
    private func updateRecentItems() {
        // Get actual processed items from the AI pipeline
        #if !MEETING_ONLY
        let pipelineItems = appStore.aiPipeline.getRecentProcessedItems()
        #else
        let pipelineItems: [ProcessedItemResult] = []
        #endif
        
        // Convert to UI model
        recentProcessedItems = pipelineItems.map { pipelineItem in
            ProcessedItem(
                id: pipelineItem.id,
                originalContent: pipelineItem.originalContent,
                source: pipelineItem.source,
                tags: pipelineItem.tags,
                aiOutput: AIOutput(
                    summary: pipelineItem.aiSummary,
                    extractedTags: pipelineItem.tags.map { $0.rawValue },
                    confidence: pipelineItem.confidence,
                    processingTime: pipelineItem.processingTime
                ),
                timestamp: pipelineItem.timestamp
            )
        }
    }
}

struct AIMonitorHeader: View {
    @Binding var isExpanded: Bool
    @Binding var selectedTab: Int
    let stats: PipelineStatistics
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                    
                    Text("AI Monitor")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // Live indicator
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .scaleEffect(1.0, anchor: .center)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: UUID())
                }
                
                Text("Pipeline Status: Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Quick stats
            HStack(spacing: 16) {
                StatBadgeSmall(
                    value: "\(stats.totalItemsProcessed)",
                    label: "Processed",
                    color: .green
                )
                
                StatBadgeSmall(
                    value: "\(stats.itemsFiltered)",
                    label: "Filtered",
                    color: .orange
                )
                
                StatBadgeSmall(
                    value: "\(stats.activeTasks)",
                    label: "Tasks",
                    color: .blue
                )
            }
            
            // Expand/collapse button
            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

struct StatBadgeSmall: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct LiveProcessingView: View {
    let processingItems: [ProcessingItem]
    let isExpanded: Bool
    
    var body: some View {
        if processingItems.isEmpty {
            EmptyStateView(
                icon: "brain.head.profile",
                title: "No Active Processing",
                subtitle: "AI pipeline is idle"
            )
        } else {
            List(processingItems) { item in
                ProcessingItemRow(item: item, isExpanded: isExpanded)
            }
            .listStyle(.plain)
        }
    }
}

struct ProcessingItemRow: View {
    let item: ProcessingItem
    let isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Source icon
                Image(systemName: sourceIcon)
                    .foregroundColor(priorityColor)
                    .frame(width: 16)
                
                // Content preview
                Text(contentPreview)
                    .font(.caption)
                    .lineLimit(isExpanded ? 3 : 1)
                
                Spacer()
                
                // Priority indicator
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
            }
            
            if isExpanded {
                HStack {
                    Text("Source: \(item.source.description)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Priority: \(item.priority.description)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var contentPreview: String {
        let preview = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.count > 60 ? String(preview.prefix(60)) + "..." : preview
    }
    
    private var sourceIcon: String {
        switch item.source {
        case .clipboard:
            return "doc.on.clipboard"
        case .screenCapture:
            return "camera.viewfinder"
        case .email:
            return "envelope"
        case .browser:
            return "safari"
        case .meeting:
            return "video"
        case .manual:
            return "pencil"
        }
    }
    
    private var priorityColor: Color {
        switch item.priority {
        case .low:
            return .gray
        case .medium:
            return .blue
        case .high:
            return .orange
        case .urgent:
            return .red
        }
    }
}

struct RecentResultsView: View {
    let recentItems: [ProcessedItem]
    let isExpanded: Bool
    
    var body: some View {
        if recentItems.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No Recent Results",
                subtitle: "Start using the app to see AI processing results"
            )
        } else {
            List(recentItems) { item in
                ProcessedItemRow(item: item, isExpanded: isExpanded)
            }
            .listStyle(.plain)
        }
    }
}

struct ProcessedItemRow: View {
    let item: ProcessedItem
    let isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Source icon
                Image(systemName: sourceIcon)
                    .foregroundColor(.blue)
                    .frame(width: 16)
                
                // Original content preview
                Text(contentPreview)
                    .font(.caption)
                    .lineLimit(1)
                
                Spacer()
                
                // Confidence indicator
                ConfidenceBadge(confidence: item.aiOutput.confidence)
            }
            
            // AI Output
            VStack(alignment: .leading, spacing: 4) {
                if !item.aiOutput.summary.isEmpty {
                    HStack {
                        Text("AI Summary:")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text(item.aiOutput.summary)
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                }
                
                if !item.aiOutput.extractedTags.isEmpty {
                    HStack {
                        Text("Tags:")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            ForEach(Array(item.aiOutput.extractedTags.prefix(3)), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                if isExpanded {
                    HStack {
                        Text("Processing time: \(String(format: "%.2f", item.aiOutput.processingTime))s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(timeAgoString(from: item.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var contentPreview: String {
        let preview = item.originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.count > 40 ? String(preview.prefix(40)) + "..." : preview
    }
    
    private var sourceIcon: String {
        switch item.source {
        case .clipboard:
            return "doc.on.clipboard"
        case .screenCapture:
            return "camera.viewfinder"
        case .email:
            return "envelope"
        case .browser:
            return "safari"
        case .meeting:
            return "video"
        case .manual:
            return "pencil"
        }
    }
    
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
}

struct ConfidenceBadge: View {
    let confidence: Double
    
    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor)
            .cornerRadius(4)
    }
    
    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PipelineStatsView: View {
    let stats: PipelineStatistics
    let agentStatus: [AgentStatus]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Overall Statistics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pipeline Statistics")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        StatCard(
                            title: "Total Processed",
                            value: "\(stats.totalItemsProcessed)",
                            icon: "tray.full",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Items Filtered",
                            value: "\(stats.itemsFiltered)",
                            icon: "line.3.horizontal.decrease.circle",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "Vector Database",
                            value: "\(stats.vectorDatabaseSize)",
                            icon: "cylinder",
                            color: .purple
                        )
                        
                        StatCard(
                            title: "Active Tasks",
                            value: "\(stats.activeTasks)",
                            icon: "list.bullet.circle",
                            color: .green
                        )
                    }
                }
                
                Divider()
                
                // Agent Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent Status")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    ForEach(agentStatus, id: \.type) { agent in
                        AgentStatusRow(agent: agent)
                    }
                }
                
                Divider()
                
                // Filter Efficiency
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filter Efficiency")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Efficiency Rate:")
                            .font(.body)
                        
                        Spacer()
                        
                        Text("\(String(format: "%.1f", stats.filterEfficiency * 100))%")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(efficiencyColor)
                    }
                    
                    ProgressView(value: stats.filterEfficiency)
                        .progressViewStyle(.linear)
                        .tint(efficiencyColor)
                }
            }
            .padding()
        }
    }
    
    private var efficiencyColor: Color {
        if stats.filterEfficiency >= 0.8 {
            return .green
        } else if stats.filterEfficiency >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AgentStatusRow: View {
    let agent: AgentStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(agent.isActive ? .green : .red)
                .frame(width: 8, height: 8)
            
            Text(agent.name)
                .font(.body)
            
            Spacer()
            
            Text("\(agent.processedCount)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Data Models

struct ProcessedItem: Identifiable {
    let id: UUID
    let originalContent: String
    let source: ContentSource
    let tags: [ContentTag]
    let aiOutput: AIOutput
    let timestamp: Date
}

struct AIOutput {
    let summary: String
    let extractedTags: [String]
    let confidence: Double
    let processingTime: TimeInterval
}

// MARK: - Extensions

extension ProcessingPriority {
    var description: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .urgent:
            return "Urgent"
        }
    }
}

#Preview {
    AIMonitorWidget()
        .environmentObject(AppStore.shared)
        .frame(width: 600, height: 500)
}