import Foundation
import Combine
import OSLog

// MARK: - Agent Communication Protocol

/// Protocol for agent communication bus enabling inter-agent messaging
protocol AgentCommunicationBus: AnyObject {
    /// Send a message to a specific agent
    func sendMessage(_ message: AgentMessage, to: AgentSpecialization) async
    
    /// Broadcast a message to all agents
    func broadcast(_ message: AgentMessage) async
    
    /// Subscribe to specific message types
    func subscribe(to messageType: MessageType, handler: @escaping (AgentMessage) async -> Void) -> AnyCancellable
    
    /// Register an agent with the communication bus
    func registerAgent(_ agent: any AIAgent)
    
    /// Unregister an agent from the communication bus
    func unregisterAgent(_ agentID: UUID)
}

// MARK: - Agent Specialization

enum AgentSpecialization: String, CaseIterable, Codable {
    case communicationAnalyzer = "communication_analyzer"
    case contextTracker = "context_tracker"
    case reminderManager = "reminder_manager"
    case screenAnalyzer = "screen_analyzer"
    case actionPrioritizer = "action_prioritizer"
    case meetingTranscriber = "meeting_transcriber"
    case searchCoordinator = "search_coordinator"
    case contentFiltering = "content_filtering"
    case contentTagging = "content_tagging"
    case commitmentDetection = "commitment_detection"
    case followupTracking = "followup_tracking"
    case contextCorrelation = "context_correlation"
    case smartReminder = "smart_reminder"
}

// MARK: - Message Types

enum MessageType: String, Codable {
    case contentProcessed = "content_processed"
    case commitmentDetected = "commitment_detected"
    case actionRequired = "action_required"
    case contextUpdate = "context_update"
    case reminderScheduled = "reminder_scheduled"
    case taskCompleted = "task_completed"
    case collaborationRequest = "collaboration_request"
    case urgentNotification = "urgent_notification"
    case searchRequest = "search_request"
    case analysisComplete = "analysis_complete"
}

// MARK: - Agent Message

struct AgentMessage: Identifiable, Codable, CustomStringConvertible {
    let id: UUID
    let type: MessageType
    let from: AgentSpecialization
    let to: AgentSpecialization?
    let content: MessageContent
    let timestamp: Date
    let priority: MessagePriority
    let correlationId: UUID?
    
    init(
        type: MessageType,
        from: AgentSpecialization,
        to: AgentSpecialization? = nil,
        content: MessageContent,
        priority: MessagePriority = .normal,
        correlationId: UUID? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.from = from
        self.to = to
        self.content = content
        self.timestamp = Date()
        self.priority = priority
        self.correlationId = correlationId
    }
    
    var description: String {
        return "AgentMessage(type: \(type.rawValue), from: \(from.rawValue), to: \(to?.rawValue ?? "broadcast"))"
    }
}

enum MessagePriority: Int, Codable, Comparable {
    case low = 1
    case normal = 2
    case high = 3
    case urgent = 4
    
    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Message Content

enum MessageContent: Codable {
    case text(String)
    case commitment(CommitmentInfo)
    case action(ActionInfo)
    case context(ContextInfo)
    case searchQuery(SearchQueryInfo)
    case analysisResult(AnalysisResultInfo)
    case collaborationData(CollaborationInfo)
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .data)
            self = .text(text)
        case "commitment":
            let info = try container.decode(CommitmentInfo.self, forKey: .data)
            self = .commitment(info)
        case "action":
            let info = try container.decode(ActionInfo.self, forKey: .data)
            self = .action(info)
        case "context":
            let info = try container.decode(ContextInfo.self, forKey: .data)
            self = .context(info)
        case "searchQuery":
            let info = try container.decode(SearchQueryInfo.self, forKey: .data)
            self = .searchQuery(info)
        case "analysisResult":
            let info = try container.decode(AnalysisResultInfo.self, forKey: .data)
            self = .analysisResult(info)
        case "collaborationData":
            let info = try container.decode(CollaborationInfo.self, forKey: .data)
            self = .collaborationData(info)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message content type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .data)
        case .commitment(let info):
            try container.encode("commitment", forKey: .type)
            try container.encode(info, forKey: .data)
        case .action(let info):
            try container.encode("action", forKey: .type)
            try container.encode(info, forKey: .data)
        case .context(let info):
            try container.encode("context", forKey: .type)
            try container.encode(info, forKey: .data)
        case .searchQuery(let info):
            try container.encode("searchQuery", forKey: .type)
            try container.encode(info, forKey: .data)
        case .analysisResult(let info):
            try container.encode("analysisResult", forKey: .type)
            try container.encode(info, forKey: .data)
        case .collaborationData(let info):
            try container.encode("collaborationData", forKey: .type)
            try container.encode(info, forKey: .data)
        }
    }
}

// MARK: - Message Content Types

struct CommitmentInfo: Codable {
    let commitmentId: UUID
    let description: String
    let participants: [String]
    let deadline: Date?
    let source: ContentSource
    let confidence: Double
}

struct ActionInfo: Codable {
    let actionId: UUID
    let description: String
    let urgency: ProcessingPriority
    let dueDate: Date?
    let relatedCommitmentId: UUID?
}

struct ContextInfo: Codable {
    let contextId: UUID
    let conversationThread: String?
    let participants: [String]
    let platform: String
    let relatedContent: [UUID]
}

struct SearchQueryInfo: Codable {
    let query: String
    let searchScope: AgentSearchScope
    let timeRange: DateInterval?
    let requiredTags: [ContentTag]?
}

enum AgentSearchScope: String, Codable {
    case all
    case clipboard
    case browser
    case conversations
    case commitments
    case actions
}

struct AnalysisResultInfo: Codable {
    let analysisId: UUID
    let contentId: UUID
    let findings: [String: Any]
    let confidence: Double
    let suggestedActions: [String]
    
    enum CodingKeys: String, CodingKey {
        case analysisId, contentId, confidence, suggestedActions
        case findings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        analysisId = try container.decode(UUID.self, forKey: .analysisId)
        contentId = try container.decode(UUID.self, forKey: .contentId)
        confidence = try container.decode(Double.self, forKey: .confidence)
        suggestedActions = try container.decode([String].self, forKey: .suggestedActions)
        
        // Decode findings as JSON data
        if let findingsData = try? container.decode(Data.self, forKey: .findings),
           let findingsDict = try? JSONSerialization.jsonObject(with: findingsData) as? [String: Any] {
            findings = findingsDict
        } else {
            findings = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(analysisId, forKey: .analysisId)
        try container.encode(contentId, forKey: .contentId)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(suggestedActions, forKey: .suggestedActions)
        
        // Encode findings as JSON data
        if let findingsData = try? JSONSerialization.data(withJSONObject: findings) {
            try container.encode(findingsData, forKey: .findings)
        }
    }
    
    init(analysisId: UUID, contentId: UUID, findings: [String: Any], confidence: Double, suggestedActions: [String]) {
        self.analysisId = analysisId
        self.contentId = contentId
        self.findings = findings
        self.confidence = confidence
        self.suggestedActions = suggestedActions
    }
}

struct CollaborationInfo: Codable {
    let requestId: UUID
    let requestingAgent: AgentSpecialization
    let targetAgents: [AgentSpecialization]
    let taskDescription: String
    let sharedData: Data?
}

// MARK: - Communication Bus Implementation

@MainActor
class DefaultAgentCommunicationBus: AgentCommunicationBus {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "CommunicationBus")
    
    // Message queue and processing
    private var messageQueue = PriorityQueue<AgentMessage>()
    private let messageSubject = PassthroughSubject<AgentMessage, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // Agent registry
    private var registeredAgents: [AgentSpecialization: any AIAgent] = [:]
    private var agentSubscriptions: [MessageType: [(AgentMessage) async -> Void]] = [:]
    
    // Processing state
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "agent.communication", qos: .userInitiated)
    
    init() {
        startMessageProcessing()
    }
    
    // MARK: - Agent Registration
    
    func registerAgent(_ agent: any AIAgent) {
        registeredAgents[agent.specialization] = agent
        logger.info("Registered agent: \(agent.specialization.rawValue)")
    }
    
    func unregisterAgent(_ agentID: UUID) {
        registeredAgents = registeredAgents.filter { $0.value.agentID != agentID }
        logger.info("Unregistered agent: \(agentID)")
    }
    
    // MARK: - Message Handling
    
    func sendMessage(_ message: AgentMessage, to specialization: AgentSpecialization) async {
        var targetedMessage = message
        if message.to == nil {
            targetedMessage = AgentMessage(
                type: message.type,
                from: message.from,
                to: specialization,
                content: message.content,
                priority: message.priority,
                correlationId: message.correlationId
            )
        }
        
        messageQueue.enqueue(targetedMessage, priority: message.priority.rawValue)
        messageSubject.send(targetedMessage)
        
        logger.debug("Message sent from \(message.from.rawValue) to \(specialization.rawValue)")
    }
    
    func broadcast(_ message: AgentMessage) async {
        for specialization in registeredAgents.keys {
            if specialization != message.from {
                await sendMessage(message, to: specialization)
            }
        }
        
        logger.debug("Broadcast message from \(message.from.rawValue)")
    }
    
    func subscribe(to messageType: MessageType, handler: @escaping (AgentMessage) async -> Void) -> AnyCancellable {
        if agentSubscriptions[messageType] == nil {
            agentSubscriptions[messageType] = []
        }
        agentSubscriptions[messageType]?.append(handler)
        
        return messageSubject
            .filter { $0.type == messageType }
            .sink { message in
                Task {
                    await handler(message)
                }
            }
    }
    
    // MARK: - Message Processing
    
    private func startMessageProcessing() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task {
                await self.processMessageQueue()
            }
        }
    }
    
    private func processMessageQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        // Process up to 10 messages at a time
        var processedCount = 0
        while processedCount < 10, let message = messageQueue.dequeue() {
            await deliverMessage(message)
            processedCount += 1
        }
    }
    
    private func deliverMessage(_ message: AgentMessage) async {
        // Deliver to specific agent if targeted
        if let targetSpecialization = message.to,
           let targetAgent = registeredAgents[targetSpecialization] {
            await targetAgent.receiveMessage(message)
        }
        
        // Deliver to subscribers
        if let handlers = agentSubscriptions[message.type] {
            for handler in handlers {
                await handler(message)
            }
        }
        
        logger.debug("Delivered message \(message.id) of type \(message.type.rawValue)")
    }
}

// MARK: - Priority Queue Implementation

struct PriorityQueue<T> {
    private var heap: [(element: T, priority: Int)] = []
    
    mutating func enqueue(_ element: T, priority: Int) {
        heap.append((element, priority))
        heap.sort { $0.priority > $1.priority }
    }
    
    mutating func dequeue() -> T? {
        guard !heap.isEmpty else { return nil }
        return heap.removeFirst().element
    }
    
    var isEmpty: Bool {
        return heap.isEmpty
    }
    
    var count: Int {
        return heap.count
    }
}