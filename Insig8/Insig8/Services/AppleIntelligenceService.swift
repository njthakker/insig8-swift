import SwiftUI
import Combine
import EventKit
import AppKit
import OSLog
import Speech
import Vision
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Comprehensive AI Service (Phase 4B)
@MainActor
class AppleIntelligenceService: ObservableObject {
    // MARK: - Published Properties
    @Published var isAIAvailable: Bool = false
    @Published var isProcessing: Bool = false
    @Published var lastError: String?
    @Published var foundationModelsEnabled: Bool = false
    
    // MARK: - Core Services
#if canImport(FoundationModels)
    private var languageSession: LanguageModelSession?
    private var commandSession: LanguageModelSession?
    private var analysisSession: LanguageModelSession?
#endif
    
    private let logger = Logger(subsystem: "com.insig8.ai", category: "AppleIntelligence")
    private let nlProcessor = NaturalLanguage.NLLanguageRecognizer()
    
    // MARK: - Initialization
    init() {
        Task {
            await checkAIAvailability()
            await initializeFoundationModels()
        }
    }
    
    // MARK: - AI Availability Check
    private func checkAIAvailability() async {
#if canImport(FoundationModels)
        // Check if Foundation Models are available using SystemLanguageModel
        let model = FoundationModels.SystemLanguageModel.default
        switch model.availability {
        case .available:
            foundationModelsEnabled = true
            isAIAvailable = true
            logger.info("Foundation Models available - using Apple Intelligence")
        case .unavailable(.deviceNotEligible):
            foundationModelsEnabled = false
            isAIAvailable = true // Fall back to rule-based
            logger.warning("Device not eligible for Foundation Models - using fallback")
        case .unavailable(.appleIntelligenceNotEnabled):
            foundationModelsEnabled = false
            isAIAvailable = true
            logger.warning("Apple Intelligence not enabled - using fallback")
        case .unavailable(.modelNotReady):
            foundationModelsEnabled = false
            isAIAvailable = true
            logger.warning("Foundation Models not ready - using fallback")
        case .unavailable(_):
            foundationModelsEnabled = false
            isAIAvailable = true
            logger.warning("Foundation Models unavailable for unknown reason - using fallback")
        @unknown default:
            foundationModelsEnabled = false
            isAIAvailable = true
            logger.warning("Unknown Foundation Models status - using fallback")
        }
#else
        foundationModelsEnabled = false
        isAIAvailable = true
        logger.info("Foundation Models framework not available - using rule-based implementations")
#endif
        lastError = nil
    }
    
    private func initializeFoundationModels() async {
#if canImport(FoundationModels)
        guard foundationModelsEnabled else { return }
        
        // Initialize specialized sessions for different AI tasks
        languageSession = LanguageModelSession {
            "You are an intelligent assistant for a macOS command palette app called Insig8. You help users with natural language commands, content analysis, and productivity tasks. Always be concise and helpful."
        }
        
        commandSession = LanguageModelSession {
            "You are a command interpreter for Insig8. Parse natural language commands and identify user intent for widget navigation, searches, and actions. Be precise and confident in your interpretations."
        }
        
        analysisSession = LanguageModelSession {
            "You are a content analyst for Insig8. Analyze text content to detect commitments, extract action items, identify important information, and suggest relevant actions. Focus on productivity and task management."
        }
        
        logger.info("Foundation Models sessions initialized successfully")
#endif
    }
    
    // MARK: - Core AI Functions
    
    /// Process natural language command and return structured response
    func processNaturalLanguageCommand(_ input: String) async -> CommandInterpretation? {
        guard !input.isEmpty else { return nil }
        
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        if foundationModelsEnabled, let session = commandSession {
            return await processCommandWithFoundationModels(input, session: session)
        }
#endif
        
        // Fallback to rule-based processing
        return processCommandWithRules(input)
    }
    
#if canImport(FoundationModels)
    private func processCommandWithFoundationModels(_ input: String, session: LanguageModelSession) async -> CommandInterpretation? {
        // Check if session is already responding
        guard !session.isResponding else {
            logger.warning("Foundation Models session is busy, falling back to rule-based processing")
            return processCommandWithRules(input)
        }
        
        do {
            let commandAnalysis = try await session.respond(
                to: """
                Analyze this command and determine the user's intent: "\(input)"
                
                Available widgets: calendar, clipboard, settings, search, translation, emoji, calculator, systemActions, windowManager, processManager, networkInfo, shortcuts
                
                Return the intent classification, target widget (if any), action description, extracted parameters, and confidence score.
                """,
                generating: CommandAnalysisResult.self
            )
            
            return CommandInterpretation(
                intent: CommandIntent(rawValue: commandAnalysis.content.intent) ?? .unknown,
                targetWidget: commandAnalysis.content.targetWidget.flatMap { WidgetType(rawValue: $0) },
                action: commandAnalysis.content.action,
                parameters: commandAnalysis.content.parameters,
                confidence: commandAnalysis.content.confidence
            )
        } catch {
            logger.error("Foundation Models command processing failed: \(error.localizedDescription)")
            return processCommandWithRules(input)
        }
    }
#endif
    
    private func processCommandWithRules(_ input: String) -> CommandInterpretation? {
        let lowercaseInput = input.lowercased()
        
        // Enhanced pattern matching for common commands
        if lowercaseInput.contains("calendar") || lowercaseInput.contains("event") || lowercaseInput.contains("schedule") {
            return CommandInterpretation(
                intent: .openWidget,
                targetWidget: .calendar,
                action: "Open calendar widget",
                parameters: [],
                confidence: 0.8
            )
        } else if lowercaseInput.contains("clipboard") || lowercaseInput.contains("copy") || lowercaseInput.contains("paste") {
            return CommandInterpretation(
                intent: .openWidget,
                targetWidget: .clipboard,
                action: "Open clipboard widget",
                parameters: [],
                confidence: 0.8
            )
        } else if lowercaseInput.contains("settings") || lowercaseInput.contains("preferences") || lowercaseInput.contains("config") {
            return CommandInterpretation(
                intent: .openWidget,
                targetWidget: .settings,
                action: "Open settings widget",
                parameters: [],
                confidence: 0.8
            )
        } else if lowercaseInput.contains("search") || lowercaseInput.contains("find") {
            let searchTerms = input.components(separatedBy: " ").filter { 
                !["search", "find", "for", "the", "a", "an"].contains($0.lowercased()) 
            }
            return CommandInterpretation(
                intent: .search,
                targetWidget: nil,
                action: "Perform search",
                parameters: searchTerms,
                confidence: 0.7
            )
        }
        
        return CommandInterpretation(
            intent: .unknown,
            targetWidget: nil,
            action: "Unknown command",
            parameters: [],
            confidence: 0.1
        )
    }
    
    /// Generate intelligent suggestions based on context
    func generateSuggestions(for context: AppContext) async -> [String] {
        isProcessing = true
        defer { isProcessing = false }
        
        var suggestions: [String] = []
        
        // Time-based suggestions
        let hour = Calendar.current.component(.hour, from: context.currentTime)
        if hour < 12 {
            suggestions.append("Check morning calendar events")
            suggestions.append("Review overnight clipboard items")
        } else if hour < 17 {
            suggestions.append("View afternoon schedule")
            suggestions.append("Quick calculator access")
        } else {
            suggestions.append("Tomorrow's calendar preview")
            suggestions.append("Evening productivity settings")
        }
        
        // Context-based suggestions
        if context.activeWidget == .calendar {
            suggestions.append("Create new event")
            suggestions.append("Switch to clipboard")
        } else if context.activeWidget == .clipboard {
            suggestions.append("Clear clipboard history")
            suggestions.append("Switch to calendar")
        }
        
        return Array(suggestions.prefix(3))
    }
    
    /// Enhance clipboard content with AI insights
    func enhanceClipboardContent(_ content: String) async -> ClipboardEnhancement? {
        guard !content.isEmpty else { return nil }
        
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        if foundationModelsEnabled, let session = analysisSession {
            return await enhanceContentWithFoundationModels(content, session: session)
        }
#endif
        
        // Fallback to rule-based analysis
        return enhanceContentWithRules(content)
    }
    
#if canImport(FoundationModels)
    private func enhanceContentWithFoundationModels(_ content: String, session: LanguageModelSession) async -> ClipboardEnhancement? {
        // Check if session is already responding
        guard !session.isResponding else {
            logger.warning("Foundation Models session is busy, falling back to rule-based processing")
            return enhanceContentWithRules(content)
        }
        
        do {
            let contentAnalysis = try await session.respond(
                to: """
                Analyze this clipboard content and provide insights: "\(content)"
                
                Determine:
                1. Content type (text, email, url, code, phoneNumber, address, date)
                2. A concise summary (max 50 words)
                3. 3 most relevant suggested actions
                4. Confidence score (0.0 to 1.0)
                
                Focus on productivity and usefulness for a command palette app user.
                """,
                generating: ContentAnalysisResult.self
            )
            
            return ClipboardEnhancement(
                summary: contentAnalysis.content.summary,
                contentType: ContentType(rawValue: contentAnalysis.content.contentType) ?? .text,
                suggestedActions: contentAnalysis.content.suggestedActions,
                confidence: contentAnalysis.content.confidence
            )
        } catch {
            logger.error("Foundation Models content analysis failed: \(error.localizedDescription)")
            return enhanceContentWithRules(content)
        }
    }
#endif
    
    private func enhanceContentWithRules(_ content: String) -> ClipboardEnhancement? {
        let contentType = detectContentType(content)
        let summary = createSummary(content)
        let actions = suggestActions(for: content, type: contentType)
        
        return ClipboardEnhancement(
            summary: summary,
            contentType: contentType,
            suggestedActions: actions,
            confidence: 0.7
        )
    }
    
    /// Smart search with semantic understanding
    func enhanceSearch(query: String, context: SearchContext) async -> [SearchSuggestion] {
        isProcessing = true
        defer { isProcessing = false }
        
        var suggestions: [SearchSuggestion] = []
        
        // Basic search enhancement
        if query.count >= 3 {
            suggestions.append(SearchSuggestion(
                term: query + "*",
                filter: "wildcard",
                reasoning: "Include partial matches"
            ))
            
            suggestions.append(SearchSuggestion(
                term: "related:" + query,
                filter: "semantic",
                reasoning: "Find related items"
            ))
        }
        
        return suggestions
    }
    
    // MARK: - Advanced AI Capabilities
    
    /// Detect commitments in text content
    func detectCommitment(in text: String, source: CommitmentSource = .manual) async -> CommitmentAnalysis? {
        guard !text.isEmpty else { return nil }
        
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        if foundationModelsEnabled, let session = analysisSession {
            return await detectCommitmentWithFoundationModels(text, source: source, session: session)
        }
#endif
        
        return detectCommitmentWithRules(text, source: source)
    }
    
#if canImport(FoundationModels)
    private func detectCommitmentWithFoundationModels(_ text: String, source: CommitmentSource, session: LanguageModelSession) async -> CommitmentAnalysis? {
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this text for commitments or promises: "\(text)"
                
                Look for phrases indicating the user has committed to:
                - Reply to someone
                - Complete a task
                - Follow up on something
                - Provide information
                - Take action
                
                Extract:
                - Whether there's a commitment (true/false)
                - The commitment text
                - Who it's for (recipient)
                - When it's due (if mentioned)
                - Urgency level (low, medium, high, urgent)
                - Required action
                """,
                generating: CommitmentAnalysisResult.self
            )
            
            let dateFormatter = ISO8601DateFormatter()
            let parsedDueDate = analysis.content.estimatedDeadline.flatMap { dateFormatter.date(from: $0) }
            
            return CommitmentAnalysis(
                hasCommitment: analysis.content.hasCommitment,
                commitmentText: analysis.content.commitmentText,
                recipient: analysis.content.recipient,
                dueDate: parsedDueDate,
                urgencyLevel: Priority(rawValue: analysis.content.urgencyLevel) ?? .medium,
                actionRequired: analysis.content.actionRequired,
                confidence: analysis.content.confidence,
                source: source
            )
        } catch {
            logger.error("Foundation Models commitment detection failed: \(error.localizedDescription)")
            return detectCommitmentWithRules(text, source: source)
        }
    }
#endif
    
    private func detectCommitmentWithRules(_ text: String, source: CommitmentSource) -> CommitmentAnalysis? {
        let lowercaseText = text.lowercased()
        
        // Common commitment patterns
        let commitmentPatterns = [
            "i'll get back", "i'll reply", "i'll respond", "i will get back",
            "i'll look into", "i'll check", "i'll send", "i'll update",
            "will follow up", "will respond", "will reply", "will get back"
        ]
        
        let hasCommitment = commitmentPatterns.contains { lowercaseText.contains($0) }
        
        if hasCommitment {
            return CommitmentAnalysis(
                hasCommitment: true,
                commitmentText: text,
                recipient: nil,
                dueDate: nil,
                urgencyLevel: .medium,
                actionRequired: "Follow up on commitment",
                confidence: 0.7,
                source: source
            )
        }
        
        return nil
    }
    
    /// Extract action items from meeting transcript
    func extractActionItems(from transcript: String) async -> [ActionItemExtraction] {
        guard !transcript.isEmpty else { return [] }
        
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        if foundationModelsEnabled, let session = analysisSession {
            return await extractActionItemsWithFoundationModels(transcript, session: session)
        }
#endif
        
        return extractActionItemsWithRules(transcript)
    }
    
#if canImport(FoundationModels)
    private func extractActionItemsWithFoundationModels(_ transcript: String, session: LanguageModelSession) async -> [ActionItemExtraction] {
        do {
            let extraction = try await session.respond(
                to: """
                Extract action items from this meeting transcript: "\(transcript)"
                
                Look for:
                - Tasks assigned to specific people
                - Deadlines mentioned
                - Follow-up actions required
                - Decisions that need implementation
                
                For each action item, extract:
                - The task description
                - Who is assigned (if mentioned)
                - Due date (if mentioned)
                - Priority level
                - Context from the meeting
                """,
                generating: ActionItemsExtractionResult.self
            )
            
            let dateFormatter = ISO8601DateFormatter()
            
            return extraction.content.actionItems.map { item in
                let parsedDueDate = item.dueDate.flatMap { dateFormatter.date(from: $0) }
                
                return ActionItemExtraction(
                    text: item.text,
                    assignee: item.assignee,
                    dueDate: parsedDueDate,
                    priority: Priority(rawValue: item.priority) ?? .medium,
                    context: item.context,
                    confidence: item.confidence
                )
            }
        } catch {
            logger.error("Foundation Models action item extraction failed: \(error.localizedDescription)")
            return extractActionItemsWithRules(transcript)
        }
    }
#endif
    
    private func extractActionItemsWithRules(_ transcript: String) -> [ActionItemExtraction] {
        // Simple rule-based extraction
        let sentences = transcript.components(separatedBy: ".")
        var actionItems: [ActionItemExtraction] = []
        
        for sentence in sentences {
            let lowercased = sentence.lowercased()
            if lowercased.contains("action item") || lowercased.contains("todo") || lowercased.contains("follow up") {
                actionItems.append(ActionItemExtraction(
                    text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    assignee: nil,
                    dueDate: nil,
                    priority: .medium,
                    context: "Extracted from meeting",
                    confidence: 0.6
                ))
            }
        }
        
        return actionItems
    }
    
    /// Analyze screen content for important information
    func analyzeScreenContent(_ ocrText: String, appName: String) async -> ScreenAnalysis? {
        guard !ocrText.isEmpty else { return nil }
        
        isProcessing = true
        defer { isProcessing = false }
        
#if canImport(FoundationModels)
        if foundationModelsEnabled, let session = analysisSession {
            return await analyzeScreenWithFoundationModels(ocrText, appName: appName, session: session)
        }
#endif
        
        return analyzeScreenWithRules(ocrText, appName: appName)
    }
    
#if canImport(FoundationModels)
    private func analyzeScreenWithFoundationModels(_ ocrText: String, appName: String, session: LanguageModelSession) async -> ScreenAnalysis? {
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this screen content from \(appName): "\(ocrText)"
                
                Look for:
                - Unread messages or notifications
                - Questions that need responses
                - Commitments or promises made
                - Important deadlines or dates
                - Action items or tasks
                
                Identify:
                - Key messages or content
                - Who is involved
                - What actions might be needed
                - Urgency level
                - Context and meaning
                """,
                generating: ScreenAnalysisResult.self
            )
            
            return ScreenAnalysis(
                appName: appName,
                keyMessages: analysis.content.keyMessages,
                detectedCommitments: analysis.content.detectedCommitments,
                unrespondedItems: analysis.content.unrespondedItems,
                urgencyLevel: Priority(rawValue: analysis.content.urgencyLevel) ?? .low,
                suggestedActions: analysis.content.suggestedActions,
                confidence: analysis.content.confidence
            )
        } catch {
            logger.error("Foundation Models screen analysis failed: \(error.localizedDescription)")
            return analyzeScreenWithRules(ocrText, appName: appName)
        }
    }
#endif
    
    private func analyzeScreenWithRules(_ ocrText: String, appName: String) -> ScreenAnalysis? {
        // Basic analysis for common patterns
        let lowercased = ocrText.lowercased()
        var keyMessages: [String] = []
        var suggestedActions: [String] = []
        
        if lowercased.contains("unread") || lowercased.contains("new message") {
            keyMessages.append("Unread messages detected")
            suggestedActions.append("Check messages")
        }
        
        if lowercased.contains("?") {
            keyMessages.append("Questions detected")
            suggestedActions.append("Review and respond")
        }
        
        return ScreenAnalysis(
            appName: appName,
            keyMessages: keyMessages,
            detectedCommitments: [],
            unrespondedItems: [],
            urgencyLevel: .low,
            suggestedActions: suggestedActions,
            confidence: 0.5
        )
    }
    
    // MARK: - Helper Methods
    
    private func detectContentType(_ content: String) -> ContentType {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return .url
        } else if trimmed.contains("@") && trimmed.contains(".") {
            return .email
        } else if trimmed.contains("def ") || trimmed.contains("function ") || trimmed.contains("class ") {
            return .code
        } else if trimmed.range(of: #"\d{3}-\d{3}-\d{4}"#, options: .regularExpression) != nil {
            return .phoneNumber
        } else {
            return .text
        }
    }
    
    private func createSummary(_ content: String) -> String {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.count <= 10 {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return words.prefix(8).joined(separator: " ") + "..."
        }
    }
    
    private func suggestActions(for content: String, type: ContentType) -> [String] {
        switch type {
        case .url:
            return ["Open in browser", "Copy URL", "Save bookmark"]
        case .email:
            return ["Send email", "Copy address", "Add to contacts"]
        case .code:
            return ["Format code", "Search documentation", "Save snippet"]
        case .phoneNumber:
            return ["Call number", "Send message", "Add to contacts"]
        default:
            return ["Copy text", "Search web", "Save note"]
        }
    }
}

// MARK: - Core Data Models

struct CommandInterpretation {
    let intent: CommandIntent
    let targetWidget: WidgetType?
    let action: String
    let parameters: [String]
    let confidence: Double
}

enum CommandIntent: String, CaseIterable {
    case openWidget = "open_widget"
    case search = "search"
    case createEvent = "create_event"
    case findFile = "find_file"
    case launchApp = "launch_app"
    case copyContent = "copy_content"
    case settings = "settings"
    case unknown = "unknown"
}

struct ClipboardEnhancement {
    let summary: String
    let contentType: ContentType
    let suggestedActions: [String]
    let confidence: Double
}

enum ContentType: String, Codable, CaseIterable {
    case text = "text"
    case email = "email"
    case url = "url"
    case code = "code"
    case phoneNumber = "phone"
    case address = "address"
    case date = "date"
    case unknown = "unknown"
}

struct SearchSuggestion {
    let term: String
    let filter: String?
    let reasoning: String
}

// MARK: - Widget Type Extension
extension WidgetType {
    var aiDescription: String {
        switch self {
        case .calendar:
            return "calendar and events"
        case .clipboard:
            return "clipboard history"
        case .settings:
            return "app settings and preferences"
        case .search:
            return "search interface"
        case .translation:
            return "text translation"
        case .emoji:
            return "emoji picker"
        case .calculator:
            return "calculator"
        case .systemActions:
            return "system actions"
        case .windowManager:
            return "window management"
        case .processManager:
            return "process management"
        case .networkInfo:
            return "network information"
        case .shortcuts:
            return "shortcuts and automation"
        case .aiMonitor:
            return "AI processing monitor"
        }
    }
}

// MARK: - Advanced AI Data Models

struct CommitmentAnalysis {
    let hasCommitment: Bool
    let commitmentText: String
    let recipient: String?
    let dueDate: Date?
    let urgencyLevel: Priority
    let actionRequired: String
    let confidence: Double
    let source: CommitmentSource
}

enum CommitmentSource: String, Codable, CaseIterable {
    case slack = "slack"
    case email = "email"
    case teams = "teams"
    case manual = "manual"
    case screenCapture = "screenCapture"
    case clipboard = "clipboard"
}

enum Priority: Int, Codable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4
}

struct ActionItemExtraction {
    let text: String
    let assignee: String?
    let dueDate: Date?
    let priority: Priority
    let context: String
    let confidence: Double
}

struct ScreenAnalysis {
    let appName: String
    let keyMessages: [String]
    let detectedCommitments: [String]
    let unrespondedItems: [String]
    let urgencyLevel: Priority
    let suggestedActions: [String]
    let confidence: Double
}

// MARK: - Enhanced Context Models

struct AppContext {
    let currentTime: Date
    let activeWidget: WidgetType?
    let recentActions: [String]
    let clipboardHistory: [String]
    let userActivity: [UserActivity]
    let activeCommitments: [CommitmentAnalysis]
}

struct SearchContext {
    let scope: SearchScope
    let availableItems: [String]
    let recentSearches: [String]
    let userPreferences: [String: Any]
    let searchHistory: [SearchHistoryItem]
}

enum SearchScope: String, CaseIterable {
    case applications = "applications"
    case files = "files"
    case clipboard = "clipboard"
    case calendar = "calendar"
    case browsing = "browsing"
    case captures = "captures"
    case all = "all"
}

struct UserActivity {
    let appName: String
    let timestamp: Date
    let action: String
    let context: String?
}

struct SearchHistoryItem {
    let query: String
    let timestamp: Date
    let results: [String]
    let selectedResult: String?
}

// MARK: - Foundation Models Data Structures

#if canImport(FoundationModels)
@Generable
struct CommandAnalysisResult: Codable {
    @Guide(description: "The intent of the command (openWidget, search, createEvent, etc.)")
    let intent: String
    
    @Guide(description: "Target widget name if applicable")
    let targetWidget: String?
    
    @Guide(description: "Description of the action to be performed")
    let action: String
    
    @Guide(description: "Extracted parameters from the command")
    let parameters: [String]
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}

@Generable
struct ContentAnalysisResult: Codable {
    @Guide(description: "Type of content: text, email, url, code, phoneNumber, address, date")
    let contentType: String
    
    @Guide(description: "Concise summary of the content, maximum 50 words")
    let summary: String
    
    @Guide(description: "Three most relevant suggested actions")
    let suggestedActions: [String]
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}


@Generable
struct ActionItemsExtractionResult: Codable {
    @Guide(description: "List of action items extracted from the transcript")
    let actionItems: [ActionItemResult]
}

@Generable
struct ActionItemResult: Codable {
    @Guide(description: "Description of the action item")
    let text: String
    
    @Guide(description: "Person assigned to the action item")
    let assignee: String?
    
    @Guide(description: "Due date for the action item if mentioned (ISO8601 format)")
    let dueDate: String?
    
    @Guide(description: "Priority level: 1=low, 2=medium, 3=high, 4=urgent")
    let priority: Int
    
    @Guide(description: "Context or additional information")
    let context: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}

@Generable
struct ScreenAnalysisResult: Codable {
    @Guide(description: "Key messages or important content found")
    let keyMessages: [String]
    
    @Guide(description: "Detected commitments or promises")
    let detectedCommitments: [String]
    
    @Guide(description: "Items that appear to need responses")
    let unrespondedItems: [String]
    
    @Guide(description: "Overall urgency level: 1=low, 2=medium, 3=high, 4=urgent")
    let urgencyLevel: Int
    
    @Guide(description: "Suggested actions based on the content")
    let suggestedActions: [String]
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}
#endif