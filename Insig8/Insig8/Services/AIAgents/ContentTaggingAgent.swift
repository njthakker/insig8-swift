import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Content Tagging Agent
class ContentTaggingAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "TaggingAgent")
    weak var delegate: AIAgentDelegate?
    
    #if canImport(FoundationModels)
    private var aiSession: LanguageModelSession?
    #endif
    
    init() {
        setupAISession()
    }
    
    private func setupAISession() {
        #if canImport(FoundationModels)
        aiSession = LanguageModelSession {
            """
            You are a content tagging AI. Analyze text and assign relevant tags for efficient categorization and retrieval.
            
            Available tags:
            - commitment: User made a promise or commitment
            - followup_required: Needs follow-up action
            - urgent_action: Requires immediate attention
            - reminder: Should be reminded about later
            - action_item: Specific task to be done
            - meeting_notes: Meeting content or notes
            - email_thread: Email communication
            - code_snippet: Programming code
            - url_link: Contains URLs
            - contact_info: Has contact information
            - deadline: Has time-sensitive deadline
            - question: Contains questions
            - important: High importance content
            - communication: Communication with others
            - task: General task or todo
            
            Assign multiple relevant tags based on content analysis.
            """
        }
        #endif
    }
    
    func generateTags(for item: ProcessingItem) async -> [ContentTag] {
        logger.info("Generating tags for content from: \(item.source)")
        
        #if canImport(FoundationModels)
        if let session = aiSession, !session.isResponding {
            return await generateTagsWithAI(item, session: session)
        } else {
            return generateTagsWithRules(item)
        }
        #else
        return generateTagsWithRules(item)
        #endif
    }
    
    #if canImport(FoundationModels)
    private func generateTagsWithAI(_ item: ProcessingItem, session: LanguageModelSession) async -> [ContentTag] {
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this content and assign relevant tags: "\(item.content)"
                
                Source: \(item.source)
                Priority: \(item.priority)
                
                Consider the content context and assign appropriate tags for:
                - Content type and category
                - Required actions
                - Urgency level
                - Communication aspects
                - Task management needs
                """,
                generating: TaggingAnalysisResult.self
            )
            
            return analysis.content.tags.compactMap { ContentTag(rawValue: $0) }
            
        } catch {
            logger.error("AI tagging analysis failed: \(error.localizedDescription)")
            return generateTagsWithRules(item)
        }
    }
    #endif
    
    private func generateTagsWithRules(_ item: ProcessingItem) -> [ContentTag] {
        var tags: [ContentTag] = []
        let content = item.content.lowercased()
        
        // Source-based tags
        switch item.source {
        case .email:
            tags.append(.email_thread)
            tags.append(.communication)
        case .meeting:
            tags.append(.meeting_notes)
            tags.append(.communication)
        case .screenCapture(let appName):
            if appName.lowercased().contains("slack") || appName.lowercased().contains("teams") {
                tags.append(.communication)
            }
        case .browser:
            tags.append(.url_link)
        default:
            break
        }
        
        // Content-based tags
        if containsCommitmentLanguage(content) {
            tags.append(.commitment)
            tags.append(.followup_required)
        }
        
        if containsUrgencyLanguage(content) {
            tags.append(.urgent_action)
            tags.append(.important)
        }
        
        if containsQuestions(content) {
            tags.append(.question)
            tags.append(.followup_required)
        }
        
        if containsDeadlineLanguage(content) {
            tags.append(.deadline)
            tags.append(.reminder)
        }
        
        if containsActionLanguage(content) {
            tags.append(.action_item)
            tags.append(.task)
        }
        
        if containsCodePatterns(content) {
            tags.append(.code_snippet)
        }
        
        if containsContactInfo(content) {
            tags.append(.contact_info)
        }
        
        if containsURLs(content) {
            tags.append(.url_link)
        }
        
        // Priority-based tags
        if item.priority == .urgent {
            tags.append(.urgent_action)
        }
        
        if item.priority == .high {
            tags.append(.important)
        }
        
        // Ensure at least one tag
        if tags.isEmpty {
            tags.append(.task)
        }
        
        return Array(Set(tags)) // Remove duplicates
    }
    
    // MARK: - Rule-based Detection Methods
    
    private func containsCommitmentLanguage(_ content: String) -> Bool {
        let commitmentPatterns = [
            "i will", "i'll", "let me", "i promise", "i'll get back",
            "i'll check", "i'll send", "i'll look into", "i'll have it ready"
        ]
        return commitmentPatterns.contains { content.contains($0) }
    }
    
    private func containsUrgencyLanguage(_ content: String) -> Bool {
        let urgencyPatterns = [
            "urgent", "asap", "immediately", "critical", "emergency",
            "deadline", "due today", "right now", "priority"
        ]
        return urgencyPatterns.contains { content.contains($0) }
    }
    
    private func containsQuestions(_ content: String) -> Bool {
        return content.contains("?") || 
               content.contains("can you") ||
               content.contains("could you") ||
               content.contains("would you") ||
               content.contains("how do") ||
               content.contains("what is") ||
               content.contains("when will")
    }
    
    private func containsDeadlineLanguage(_ content: String) -> Bool {
        let deadlinePatterns = [
            "by", "due", "deadline", "before", "until", "within",
            "today", "tomorrow", "next week", "friday", "monday"
        ]
        return deadlinePatterns.contains { content.contains($0) }
    }
    
    private func containsActionLanguage(_ content: String) -> Bool {
        let actionPatterns = [
            "todo", "task", "action item", "need to", "should", "must",
            "complete", "finish", "do", "implement", "fix", "update"
        ]
        return actionPatterns.contains { content.contains($0) }
    }
    
    private func containsCodePatterns(_ content: String) -> Bool {
        let codePatterns = [
            "function", "def ", "class ", "import ", "require(",
            "{", "}", ";", "//", "/*", "*/", "#include", "SELECT"
        ]
        return codePatterns.contains { content.contains($0) }
    }
    
    private func containsContactInfo(_ content: String) -> Bool {
        let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        let phoneRegex = try? NSRegularExpression(pattern: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b")
        
        let range = NSRange(location: 0, length: content.utf16.count)
        
        return emailRegex?.firstMatch(in: content, options: [], range: range) != nil ||
               phoneRegex?.firstMatch(in: content, options: [], range: range) != nil
    }
    
    private func containsURLs(_ content: String) -> Bool {
        return content.contains("http://") || 
               content.contains("https://") ||
               content.contains("www.") ||
               content.contains(".com") ||
               content.contains(".org") ||
               content.contains(".net")
    }
}

#if canImport(FoundationModels)
@Generable
struct TaggingAnalysisResult: Codable {
    @Guide(description: "List of relevant tags for the content")
    let tags: [String]
    
    @Guide(description: "Brief explanation of why these tags were chosen")
    let reasoning: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}
#endif