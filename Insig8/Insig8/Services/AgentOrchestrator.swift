import Foundation
import Combine
import OSLog

// MARK: - Agent Orchestrator

@MainActor
class AgentOrchestrator: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "Orchestrator")
    
    // Core Components
    private let communicationBus: AgentCommunicationBus
    private let taskDAGManager: TaskDAGManager
    private let appleIntelligence: AppleIntelligenceService
    
    // Agent Registry
    private var agents: [AgentSpecialization: any AIAgent] = [:]
    
    // Task Management
    @Published var activeTasks: [AgentTask] = []
    @Published var taskResults: [UUID: AgentResponse] = [:]
    
    // Processing State
    @Published var isProcessing = false
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.communicationBus = DefaultAgentCommunicationBus()
        self.taskDAGManager = TaskDAGManager()
        self.appleIntelligence = AppleIntelligenceService()
        
        initializeAgents()
        setupCollaborationPatterns()
    }
    
    // MARK: - Agent Initialization
    
    private func initializeAgents() {
        logger.info("Initializing agent ecosystem")
        
        // Create specialized agents
        let communicationAnalyzer = CommunicationAnalyzerAgent(communicationBus: communicationBus)
        let contextTracker = ContextTrackerAgent(communicationBus: communicationBus)
        let reminderManager = ReminderManagerAgent(communicationBus: communicationBus)
        let screenAnalyzer = ScreenAnalyzerAgent(communicationBus: communicationBus)
        let actionPrioritizer = ActionPrioritizerAgent(communicationBus: communicationBus)
        let meetingTranscriber = MeetingTranscriberAgent(communicationBus: communicationBus)
        let searchCoordinator = SearchCoordinatorAgent(communicationBus: communicationBus)
        
        // Register agents
        registerAgent(communicationAnalyzer)
        registerAgent(contextTracker)
        registerAgent(reminderManager)
        registerAgent(screenAnalyzer)
        registerAgent(actionPrioritizer)
        registerAgent(meetingTranscriber)
        registerAgent(searchCoordinator)
        
        // Also register existing agents from AIProcessingPipeline
        let filteringAgent = ContentFilteringAgentWrapper(communicationBus: communicationBus)
        let taggingAgent = ContentTaggingAgentWrapper(communicationBus: communicationBus)
        let commitmentAgent = CommitmentDetectionAgentWrapper(communicationBus: communicationBus)
        let followupAgent = FollowupTrackingAgentWrapper(communicationBus: communicationBus)
        let contextAgent = ContextCorrelationAgentWrapper(communicationBus: communicationBus)
        let reminderAgent = SmartReminderAgentWrapper(communicationBus: communicationBus)
        
        registerAgent(filteringAgent)
        registerAgent(taggingAgent)
        registerAgent(commitmentAgent)
        registerAgent(followupAgent)
        registerAgent(contextAgent)
        registerAgent(reminderAgent)
    }
    
    private func registerAgent(_ agent: any AIAgent) {
        agents[agent.specialization] = agent
        communicationBus.registerAgent(agent)
        logger.info("Registered agent: \(agent.specialization.rawValue)")
    }
    
    // MARK: - Collaboration Patterns
    
    private func setupCollaborationPatterns() {
        // Pattern 1: Commitment Detection Flow
        setupCommitmentDetectionFlow()
        
        // Pattern 2: Context Correlation Flow
        setupContextCorrelationFlow()
        
        // Pattern 3: Urgent Action Flow
        setupUrgentActionFlow()
        
        // Pattern 4: Search Coordination Flow
        setupSearchCoordinationFlow()
    }
    
    private func setupCommitmentDetectionFlow() {
        // When commitment is detected, notify relevant agents
        communicationBus.subscribe(to: .commitmentDetected) { [weak self] message in
            guard case .commitment(let info) = message.content else { return }
            
            // Notify reminder manager
            await self?.communicationBus.sendMessage(
                AgentMessage(
                    type: .actionRequired,
                    from: message.from,
                    to: .reminderManager,
                    content: .commitment(info),
                    priority: .high,
                    correlationId: info.commitmentId
                ),
                to: .reminderManager
            )
            
            // Notify context tracker
            await self?.communicationBus.sendMessage(
                AgentMessage(
                    type: .contextUpdate,
                    from: message.from,
                    to: .contextTracker,
                    content: .commitment(info),
                    priority: .normal,
                    correlationId: info.commitmentId
                ),
                to: .contextTracker
            )
        }.store(in: &cancellables)
    }
    
    private func setupContextCorrelationFlow() {
        // When context is updated, correlate across agents
        communicationBus.subscribe(to: .contextUpdate) { [weak self] message in
            guard case .context(_) = message.content else { return }
            
            // Broadcast context update to relevant agents
            let relevantAgents: [AgentSpecialization] = [
                .commitmentDetection,
                .followupTracking,
                .actionPrioritizer
            ]
            
            for agent in relevantAgents {
                await self?.communicationBus.sendMessage(message, to: agent)
            }
        }.store(in: &cancellables)
    }
    
    private func setupUrgentActionFlow() {
        // Handle urgent notifications with priority
        communicationBus.subscribe(to: .urgentNotification) { [weak self] message in
            self?.logger.warning("Urgent notification received: \(message)")
            
            // Immediately notify action prioritizer
            await self?.communicationBus.sendMessage(
                message,
                to: .actionPrioritizer
            )
            
            // Create high-priority task
            _ = AgentTask(
                description: "Handle urgent notification",
                type: .analysis,
                priority: .urgent,
                parameters: ["message": message],
                requiredCapabilities: [.contextAnalysis, .reminderScheduling],
                deadline: Date().addingTimeInterval(300), // 5 minutes
                correlationId: message.correlationId
            )
            
            _ = await self?.processUserRequest(UserRequest(
                id: UUID(),
                query: "urgent",
                context: ["message": message],
                priority: .urgent
            ))
        }.store(in: &cancellables)
    }
    
    private func setupSearchCoordinationFlow() {
        // Coordinate search across multiple data sources
        communicationBus.subscribe(to: .searchRequest) { [weak self] message in
            guard case .searchQuery(let queryInfo) = message.content else { return }
            
            // Distribute search to relevant agents based on scope
            var targetAgents: [AgentSpecialization] = []
            
            switch queryInfo.searchScope {
            case .all:
                targetAgents = [.searchCoordinator, .contextTracker, .screenAnalyzer]
            case .clipboard:
                targetAgents = [.searchCoordinator]
            case .browser:
                targetAgents = [.searchCoordinator]
            case .conversations:
                targetAgents = [.communicationAnalyzer, .contextTracker]
            case .commitments:
                targetAgents = [.commitmentDetection, .followupTracking]
            case .actions:
                targetAgents = [.actionPrioritizer, .reminderManager]
            }
            
            for agent in targetAgents {
                await self?.communicationBus.sendMessage(message, to: agent)
            }
        }.store(in: &cancellables)
    }
    
    // MARK: - Task Processing
    
    func processUserRequest(_ request: UserRequest) async -> ProcessingResult {
        isProcessing = true
        defer { isProcessing = false }
        
        logger.info("Processing user request: \(request.query)")
        
        // Step 1: Determine required agents
        let requiredAgents = await determineRequiredAgents(for: request)
        
        // Step 2: Create task graph
        let taskGraph = await taskDAGManager.decomposeRequest(request, agents: requiredAgents)
        
        // Step 3: Execute tasks with coordination
        return await executeCoordinatedTasks(taskGraph)
    }
    
    private func determineRequiredAgents(for request: UserRequest) async -> [AgentSpecialization] {
        // Use Apple Intelligence to analyze request and determine needed agents
        let analysis = await analyzeRequestFallback(request.query)
        
        var requiredAgents: [AgentSpecialization] = []
        
        // Map analysis results to agent specializations
        if analysis.requiresCommitmentTracking {
            requiredAgents.append(contentsOf: [.commitmentDetection, .followupTracking])
        }
        
        if analysis.requiresContextAnalysis {
            requiredAgents.append(contentsOf: [.contextTracker, .contextCorrelation])
        }
        
        if analysis.requiresReminderScheduling {
            requiredAgents.append(contentsOf: [.reminderManager, .smartReminder])
        }
        
        if analysis.requiresScreenAnalysis {
            requiredAgents.append(.screenAnalyzer)
        }
        
        if analysis.requiresSearch {
            requiredAgents.append(.searchCoordinator)
        }
        
        if analysis.requiresMeetingProcessing {
            requiredAgents.append(.meetingTranscriber)
        }
        
        // Always include filtering and tagging
        requiredAgents.append(contentsOf: [.contentFiltering, .contentTagging])
        
        return Array(Set(requiredAgents)) // Remove duplicates
    }
    
    private func executeCoordinatedTasks(_ taskGraph: TaskDAG) async -> ProcessingResult {
        var results: [UUID: AgentResponse] = [:]
        let executionOrder = taskGraph.getExecutionOrder()
        
        for taskNode in executionOrder {
            let task = taskNode.task
            
            // Check if dependencies are satisfied
            let dependencyResults = taskNode.dependencies.compactMap { results[$0.task.id] }
            guard dependencyResults.count == taskNode.dependencies.count else {
                logger.error("Dependencies not satisfied for task: \(task.id)")
                continue
            }
            
            // Find appropriate agent for task
            guard let agent = findAgentForTask(task) else {
                logger.error("No agent found for task: \(task.description)")
                continue
            }
            
            // Execute task
            do {
                let response = try await agent.processTask(task)
                results[task.id] = response
                
                // Handle collaboration requests
                if response.status == .needsCollaboration {
                    let collaborationResult = try await handleCollaboration(
                        for: task,
                        initialAgent: agent,
                        response: response
                    )
                    results[task.id] = AgentResponse(
                        taskId: task.id,
                        status: .success,
                        results: collaborationResult.combinedResults,
                        confidence: 0.8,
                        suggestedActions: [],
                        error: nil
                    )
                }
            } catch {
                logger.error("Task execution failed: \(error)")
                results[task.id] = AgentResponse(
                    taskId: task.id,
                    status: .failure,
                    results: [:],
                    confidence: 0,
                    suggestedActions: [],
                    error: error
                )
            }
        }
        
        return ProcessingResult(
            requestId: taskGraph.requestId,
            status: determineOverallStatus(results),
            results: results,
            summary: generateSummary(results),
            suggestedActions: collectSuggestedActions(results)
        )
    }
    
    private func findAgentForTask(_ task: AgentTask) -> (any AIAgent)? {
        // Find agent with required capabilities
        for (_, agent) in agents {
            let agentCapabilities = getAgentCapabilities(agent.specialization)
            if task.requiredCapabilities.allSatisfy({ agentCapabilities.contains($0) }) {
                return agent
            }
        }
        return nil
    }
    
    private func getAgentCapabilities(_ specialization: AgentSpecialization) -> Set<AgentCapability> {
        switch specialization {
        case .communicationAnalyzer:
            return [.languageProcessing, .commitmentDetection, .contextAnalysis]
        case .contextTracker:
            return [.contextAnalysis]
        case .reminderManager:
            return [.reminderScheduling]
        case .screenAnalyzer:
            return [.screenCapture, .languageProcessing]
        case .actionPrioritizer:
            return [.contextAnalysis, .reminderScheduling]
        case .meetingTranscriber:
            return [.audioTranscription, .languageProcessing]
        case .searchCoordinator:
            return [.searchCoordination]
        case .commitmentDetection:
            return [.commitmentDetection, .languageProcessing]
        case .followupTracking:
            return [.contextAnalysis, .reminderScheduling]
        case .contextCorrelation:
            return [.contextAnalysis]
        case .smartReminder:
            return [.reminderScheduling]
        default:
            return [.languageProcessing]
        }
    }
    
    private func handleCollaboration(
        for task: AgentTask,
        initialAgent: any AIAgent,
        response: AgentResponse
    ) async throws -> CollaborationResult {
        // Determine which agents to collaborate with
        let collaboratingAgents = response.suggestedActions
            .compactMap { $0.targetAgent }
            .compactMap { agents[$0] }
        
        guard !collaboratingAgents.isEmpty else {
            throw AgentError.collaborationFailed("No collaborating agents found")
        }
        
        // Initiate collaboration
        return try await initialAgent.collaborate(with: collaboratingAgents, on: task)
    }
    
    // MARK: - Result Processing
    
    private func determineOverallStatus(_ results: [UUID: AgentResponse]) -> ProcessingStatus {
        let statuses = results.values.map { $0.status }
        
        if statuses.allSatisfy({ $0 == .success }) {
            return .success
        } else if statuses.contains(.failure) {
            return .partialFailure
        } else {
            return .completed
        }
    }
    
    private func generateSummary(_ results: [UUID: AgentResponse]) -> String {
        let successCount = results.values.filter { $0.status == .success }.count
        let totalCount = results.count
        
        return "Processed \(totalCount) tasks, \(successCount) successful"
    }
    
    private func collectSuggestedActions(_ results: [UUID: AgentResponse]) -> [SuggestedAction] {
        return results.values.flatMap { $0.suggestedActions }
    }
    
    // MARK: - Public Interface
    
    func getAgentStatuses() -> [AgentStatus] {
        return agents.values.map { $0.getStatus() }
    }
    
    func resetAllAgents() {
        for agent in agents.values {
            agent.reset()
        }
        logger.info("All agents reset")
    }
    
    func getAgent(for specialization: AgentSpecialization) -> (any AIAgent)? {
        return agents[specialization]
    }
    
    // MARK: - Fallback Methods
    
    private func analyzeRequestFallback(_ query: String) async -> RequestAnalysis {
        // Simple rule-based analysis as fallback
        let lowercased = query.lowercased()
        
        return RequestAnalysis(
            requiresCommitmentTracking: lowercased.contains("commitment") || lowercased.contains("promise") || lowercased.contains("will"),
            requiresContextAnalysis: lowercased.contains("context") || lowercased.contains("conversation"),
            requiresReminderScheduling: lowercased.contains("remind") || lowercased.contains("schedule"),
            requiresScreenAnalysis: lowercased.contains("screen") || lowercased.contains("capture"),
            requiresSearch: lowercased.contains("search") || lowercased.contains("find"),
            requiresMeetingProcessing: lowercased.contains("meeting") || lowercased.contains("transcript")
        )
    }
}

// MARK: - Data Models

struct UserRequest {
    let id: UUID
    let query: String
    let context: [String: Any]
    let priority: ProcessingPriority
}

struct ProcessingResult {
    let requestId: UUID
    let status: ProcessingStatus
    let results: [UUID: AgentResponse]
    let summary: String
    let suggestedActions: [SuggestedAction]
}

enum ProcessingStatus {
    case success
    case completed
    case partialFailure
    case failure
}

// MARK: - Task DAG Manager

class TaskDAGManager {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "TaskDAG")
    
    func decomposeRequest(_ request: UserRequest, agents: [AgentSpecialization]) async -> TaskDAG {
        let dag = TaskDAG(requestId: request.id)
        
        // Create tasks based on request and available agents
        // This is a simplified implementation - in practice, this would use
        // more sophisticated task decomposition logic
        
        // Phase 1: Filtering and tagging
        if agents.contains(.contentFiltering) {
            let filterTask = AgentTask(
                description: "Filter content for relevance",
                type: .analysis,
                priority: request.priority,
                parameters: ["query": request.query],
                requiredCapabilities: [.languageProcessing],
                deadline: nil,
                correlationId: request.id
            )
            dag.addTask(filterTask)
        }
        
        if agents.contains(.contentTagging) {
            let tagTask = AgentTask(
                description: "Tag content with semantic labels",
                type: .analysis,
                priority: request.priority,
                parameters: ["query": request.query],
                requiredCapabilities: [.languageProcessing],
                deadline: nil,
                correlationId: request.id
            )
            dag.addTask(tagTask)
        }
        
        // Phase 2: Specialized processing
        for agent in agents {
            switch agent {
            case .commitmentDetection:
                let commitmentTask = AgentTask(
                    description: "Detect commitments in content",
                    type: .extraction,
                    priority: request.priority,
                    parameters: ["query": request.query],
                    requiredCapabilities: [.commitmentDetection],
                    deadline: nil,
                    correlationId: request.id
                )
                dag.addTask(commitmentTask)
                
            case .searchCoordinator:
                let searchTask = AgentTask(
                    description: "Coordinate search across data sources",
                    type: .search,
                    priority: request.priority,
                    parameters: ["query": request.query],
                    requiredCapabilities: [.searchCoordination],
                    deadline: nil,
                    correlationId: request.id
                )
                dag.addTask(searchTask)
                
            default:
                break
            }
        }
        
        return dag
    }
}

// MARK: - Task DAG

class TaskDAG {
    let requestId: UUID
    private var nodes: [TaskNode] = []
    
    init(requestId: UUID) {
        self.requestId = requestId
    }
    
    func addTask(_ task: AgentTask, dependencies: [TaskNode] = []) {
        let node = TaskNode(task: task, dependencies: dependencies)
        nodes.append(node)
    }
    
    func getExecutionOrder() -> [TaskNode] {
        // Simple topological sort for execution order
        // In practice, this would be more sophisticated
        return nodes.sorted { $0.dependencies.count < $1.dependencies.count }
    }
}

struct TaskNode {
    let task: AgentTask
    let dependencies: [TaskNode]
}

struct RequestAnalysis {
    let requiresCommitmentTracking: Bool
    let requiresContextAnalysis: Bool
    let requiresReminderScheduling: Bool
    let requiresScreenAnalysis: Bool
    let requiresSearch: Bool
    let requiresMeetingProcessing: Bool
}