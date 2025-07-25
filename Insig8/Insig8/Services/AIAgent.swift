import Foundation
import Combine
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Agent Protocol

/// Base protocol for all AI agents in the system
protocol AIAgent: ObservableObject, AnyObject {
    var agentID: UUID { get }
    var specialization: AgentSpecialization { get }
    var memory: AgentMemory { get set }
    var tools: [AITool] { get }
    var isProcessing: Bool { get }
    
    /// Process a task assigned to this agent
    func processTask(_ task: AgentTask) async throws -> AgentResponse
    
    /// Collaborate with other agents on a task
    func collaborate(with agents: [any AIAgent], on task: AgentTask) async throws -> CollaborationResult
    
    /// Receive a message from the communication bus
    func receiveMessage(_ message: AgentMessage) async
    
    /// Get agent's current status
    func getStatus() -> AgentStatus
    
    /// Reset agent state
    func reset()
}

// MARK: - Agent Memory

class AgentMemory {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "AgentMemory")
    
    // Short-term memory (circular buffer)
    private var shortTermBuffer: CircularBuffer<MemoryItem>
    
    // Working memory for current context
    private var workingMemory: [String: Any] = [:]
    
    // Long-term memory reference (vector DB)
    private let vectorDB: EnhancedVectorDatabaseService
    
    init(bufferSize: Int = 100) {
        self.shortTermBuffer = CircularBuffer<MemoryItem>(capacity: bufferSize)
        self.vectorDB = EnhancedVectorDatabaseService()
    }
    
    // MARK: - Memory Operations
    
    func store(_ item: MemoryItem) {
        shortTermBuffer.append(item)
        
        // Store important items in long-term memory
        if item.importance > 0.7 {
            Task {
                await vectorDB.storeContent(
                    item.content,
                    tags: item.tags,
                    source: item.source,
                    timestamp: item.timestamp
                )
            }
        }
    }
    
    func recall(matching query: String, limit: Int = 5) async -> [MemoryItem] {
        // Search short-term memory
        let shortTermResults = shortTermBuffer.elements.filter { item in
            item.content.localizedCaseInsensitiveContains(query)
        }.prefix(limit)
        
        // Search long-term memory
        let longTermResults = await vectorDB.intelligentSearch(query: query, limit: limit)
        
        // Combine and deduplicate results
        var combinedResults = Array(shortTermResults)
        for result in longTermResults {
            let memoryItem = MemoryItem(
                content: result.content,
                source: result.source,
                tags: result.tags,
                timestamp: result.timestamp,
                importance: Double(result.similarity)
            )
            if !combinedResults.contains(where: { $0.content == memoryItem.content }) {
                combinedResults.append(memoryItem)
            }
        }
        
        return Array(combinedResults.prefix(limit))
    }
    
    func updateWorkingMemory(key: String, value: Any) {
        workingMemory[key] = value
    }
    
    func getWorkingMemory(key: String) -> Any? {
        return workingMemory[key]
    }
    
    func clearWorkingMemory() {
        workingMemory.removeAll()
    }
    
    func getRecentMemories(count: Int = 10) -> [MemoryItem] {
        return Array(shortTermBuffer.elements.suffix(count))
    }
}

// MARK: - Memory Item

struct MemoryItem: Identifiable {
    let id = UUID()
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let timestamp: Date
    let importance: Double
}

// MARK: - Circular Buffer

struct CircularBuffer<T> {
    private var buffer: [T?]
    private var writeIndex = 0
    private var count = 0
    let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    mutating func append(_ element: T) {
        buffer[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }
    
    var elements: [T] {
        if count < capacity {
            return buffer.compactMap { $0 }
        } else {
            var result: [T] = []
            var index = writeIndex
            for _ in 0..<capacity {
                if let element = buffer[index] {
                    result.append(element)
                }
                index = (index + 1) % capacity
            }
            return result
        }
    }
    
    var isEmpty: Bool {
        return count == 0
    }
    
    mutating func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
}

// MARK: - AI Tools

protocol AITool {
    var name: String { get }
    var description: String { get }
    func execute(with parameters: [String: Any]) async throws -> Any
}

// MARK: - Agent Task

struct AgentTask: Identifiable {
    let id = UUID()
    let description: String
    let type: TaskType
    let priority: ProcessingPriority
    let parameters: [String: Any]
    let requiredCapabilities: [AgentCapability]
    let deadline: Date?
    let correlationId: UUID?
    
    enum TaskType: String, Codable {
        case analysis
        case extraction
        case monitoring
        case search
        case reminder
        case collaboration
    }
}

enum AgentCapability: String, Codable {
    case languageProcessing
    case commitmentDetection
    case contextAnalysis
    case reminderScheduling
    case searchCoordination
    case screenCapture
    case audioTranscription
}

// MARK: - Agent Response

struct AgentResponse {
    let taskId: UUID
    let status: ResponseStatus
    let results: [String: Any]
    let confidence: Double
    let suggestedActions: [SuggestedAction]
    let error: Error?
    
    enum ResponseStatus {
        case success
        case partialSuccess
        case failure
        case needsCollaboration
    }
}

struct SuggestedAction {
    let description: String
    let targetAgent: AgentSpecialization?
    let priority: ProcessingPriority
    let parameters: [String: Any]
}

// MARK: - Collaboration Result

struct CollaborationResult {
    let collaborationId: UUID
    let participatingAgents: [AgentSpecialization]
    let combinedResults: [String: Any]
    let consensus: ConsensusLevel
    let finalDecision: String?
    
    enum ConsensusLevel {
        case unanimous
        case majority
        case split
        case noConsensus
    }
}

// MARK: - Base AI Agent Implementation

@MainActor
class BaseAIAgent: NSObject, AIAgent, ObservableObject {
    let agentID = UUID()
    let specialization: AgentSpecialization
    var memory: AgentMemory
    var tools: [AITool] = []
    
    @Published var isProcessing = false
    
    private let logger: Logger
    internal let communicationBus: AgentCommunicationBus?
    
    #if canImport(FoundationModels)
    private var languageModel: LanguageModelSession?
    #endif
    
    init(
        specialization: AgentSpecialization,
        memorySize: Int = 100,
        communicationBus: AgentCommunicationBus? = nil
    ) {
        self.specialization = specialization
        self.memory = AgentMemory(bufferSize: memorySize)
        self.communicationBus = communicationBus
        self.logger = Logger(subsystem: "com.insig8.ai", category: "Agent.\(specialization.rawValue)")
        
        super.init()
        
        #if canImport(FoundationModels)
        Task {
            await initializeLanguageModel()
        }
        #endif
    }
    
    // MARK: - Language Model Initialization
    
    #if canImport(FoundationModels)
    private func initializeLanguageModel() async {
        languageModel = LanguageModelSession()
        logger.info("Language model initialized for \(self.specialization.rawValue)")
    }
    #endif
    
    // MARK: - AIAgent Protocol Implementation
    
    func processTask(_ task: AgentTask) async throws -> AgentResponse {
        isProcessing = true
        defer { isProcessing = false }
        
        logger.info("Processing task: \(task.description)")
        
        // Store task in memory
        memory.store(MemoryItem(
            content: task.description,
            source: .manual,
            tags: [.task],
            timestamp: Date(),
            importance: Double(task.priority.rawValue) / 4.0
        ))
        
        // Default implementation - subclasses should override
        return AgentResponse(
            taskId: task.id,
            status: .needsCollaboration,
            results: [:],
            confidence: 0.5,
            suggestedActions: [],
            error: nil
        )
    }
    
    func collaborate(with agents: [any AIAgent], on task: AgentTask) async throws -> CollaborationResult {
        logger.info("Starting collaboration with \(agents.count) agents")
        
        // Send collaboration request
        if let bus = communicationBus {
            let message = AgentMessage(
                type: .collaborationRequest,
                from: specialization,
                content: .collaborationData(CollaborationInfo(
                    requestId: UUID(),
                    requestingAgent: specialization,
                    targetAgents: agents.map { $0.specialization },
                    taskDescription: task.description,
                    sharedData: nil
                )),
                priority: task.priority == .urgent ? .urgent : .high
            )
            
            await bus.broadcast(message)
        }
        
        // Default collaboration implementation
        return CollaborationResult(
            collaborationId: UUID(),
            participatingAgents: [specialization] + agents.map { $0.specialization },
            combinedResults: [:],
            consensus: .noConsensus,
            finalDecision: nil
        )
    }
    
    func receiveMessage(_ message: AgentMessage) async {
        logger.debug("Received message: \(message.type.rawValue) from \(message.from.rawValue)")
        
        // Store message in memory
        memory.store(MemoryItem(
            content: "Message: \(message.type.rawValue)",
            source: .manual,
            tags: [.communication],
            timestamp: message.timestamp,
            importance: Double(message.priority.rawValue) / 4.0
        ))
        
        // Handle message based on type
        switch message.type {
        case .collaborationRequest:
            await handleCollaborationRequest(message)
        case .contextUpdate:
            await handleContextUpdate(message)
        case .urgentNotification:
            await handleUrgentNotification(message)
        default:
            // Subclasses can handle specific message types
            break
        }
    }
    
    func getStatus() -> AgentStatus {
        return AgentStatus(
            name: specialization.rawValue,
            type: mapSpecializationToType(specialization),
            isActive: !isProcessing,
            lastActivity: Date(),
            processedCount: 0 // Subclasses should track this
        )
    }
    
    func reset() {
        memory.clearWorkingMemory()
        isProcessing = false
        logger.info("Agent reset completed")
    }
    
    // MARK: - Message Handlers
    
    private func handleCollaborationRequest(_ message: AgentMessage) async {
        guard case .collaborationData(let info) = message.content else { return }
        
        logger.info("Handling collaboration request from \(info.requestingAgent.rawValue)")
        
        // Process collaboration request
        // Subclasses should implement specific collaboration logic
    }
    
    private func handleContextUpdate(_ message: AgentMessage) async {
        guard case .context(let info) = message.content else { return }
        
        // Update working memory with new context
        memory.updateWorkingMemory(key: "currentContext", value: info)
        logger.debug("Context updated: \(info.contextId)")
    }
    
    private func handleUrgentNotification(_ message: AgentMessage) async {
        logger.warning("Urgent notification received: \(message)")
        
        // Handle urgent notifications
        // Subclasses should implement specific urgent handling
    }
    
    // MARK: - Utility Methods
    
    private func mapSpecializationToType(_ specialization: AgentSpecialization) -> AIAgentType {
        switch specialization {
        case .contentFiltering:
            return .filtering
        case .contentTagging:
            return .tagging
        case .commitmentDetection:
            return .commitment
        case .followupTracking:
            return .followup
        case .contextCorrelation, .contextTracker:
            return .context
        case .smartReminder, .reminderManager:
            return .reminder
        default:
            return .filtering // Default fallback
        }
    }
    
    // MARK: - Language Model Integration
    
    #if canImport(FoundationModels)
    func queryLanguageModel(_ prompt: String) async throws -> String {
        guard let model = languageModel else {
            throw AgentError.languageModelNotAvailable
        }
        
        let response = try await model.respond(to: prompt)
        return response.content
    }
    
    func generateStructuredResponse<T: Generable>(_ prompt: String, responseType: T.Type) async throws -> T {
        guard let model = languageModel else {
            throw AgentError.languageModelNotAvailable
        }
        
        let response = try await model.respond(to: prompt, generating: responseType)
        return response.content
    }
    #endif
}

// MARK: - Agent Errors

enum AgentError: LocalizedError {
    case languageModelNotAvailable
    case processingFailed(String)
    case collaborationFailed(String)
    case invalidTask
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .languageModelNotAvailable:
            return "Language model is not available"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .collaborationFailed(let reason):
            return "Collaboration failed: \(reason)"
        case .invalidTask:
            return "Invalid task parameters"
        case .timeout:
            return "Operation timed out"
        }
    }
}