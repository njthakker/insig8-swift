import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Content Filtering Agent (First Stage Filter)
class ContentFilteringAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "FilteringAgent")
    weak var delegate: AIAgentDelegate?
    
    #if canImport(FoundationModels)
    private var aiSession: LanguageModelSession?
    #endif
    
    // Filtering statistics
    private var totalProcessed = 0
    private var filtered = 0
    private var passed = 0
    
    init() {
        setupAISession()
    }
    
    private func setupAISession() {
        #if canImport(FoundationModels)
        aiSession = LanguageModelSession {
            """
            You are a content filtering AI. Your job is to identify whether content is worth processing by other AI agents.
            
            FILTER OUT (mark as irrelevant):
            - Small talk and casual greetings ("How are you?", "Good morning", "Have a great day")
            - Weather discussions unless work-related
            - General social media content without actionable items
            - Spam or promotional content
            - Random web browsing without clear purpose
            - System notifications and automated messages
            - Casual emoji-only messages
            - "Thanks", "OK", "Got it" type acknowledgments
            - General news articles unless they contain actionable business items
            - Entertainment content (games, movies, sports) unless work-related
            
            PASS THROUGH (mark as relevant):
            - Business communications with questions or requests
            - Commitments and promises made by user
            - Action items and tasks
            - Meeting content and discussions
            - Technical discussions and code
            - Important deadlines and dates
            - Contact information and business details
            - Project-related discussions
            - Problem-solving conversations
            - Email threads requiring responses
            - Important URLs and resources
            - Any content with urgency indicators
            
            Be conservative - when in doubt, pass it through rather than filter it out.
            """
        }
        #endif
    }
    
    /// Primary filtering method - returns true if content should be processed further
    func shouldProcessContent(_ item: ProcessingItem) async -> Bool {
        totalProcessed += 1
        
        logger.info("Filtering content from: \(item.source)")
        
        // Always process high priority items
        if item.priority == .urgent {
            passed += 1
            return true
        }
        
        // Quick rule-based pre-filtering for obvious cases
        if let quickResult = quickRuleBasedFilter(item) {
            if quickResult {
                passed += 1
            } else {
                filtered += 1
                logger.debug("Quick filtered out: \(String(item.content.prefix(50)))")
            }
            return quickResult
        }
        
        // Use AI for more complex filtering
        #if canImport(FoundationModels)
        if let session = aiSession, !session.isResponding {
            let result = await filterWithAI(item, session: session)
            if result {
                passed += 1
            } else {
                filtered += 1
                logger.debug("AI filtered out: \(String(item.content.prefix(50)))")
            }
            return result
        } else {
            // Fallback to rule-based when AI is busy
            let result = detailedRuleBasedFilter(item)
            if result {
                passed += 1
            } else {
                filtered += 1
                logger.debug("Rule filtered out: \(String(item.content.prefix(50)))")
            }
            return result
        }
        #else
        let result = detailedRuleBasedFilter(item)
        if result {
            passed += 1
        } else {
            filtered += 1
            logger.debug("Rule filtered out: \(String(item.content.prefix(50)))")
        }
        return result
        #endif
    }
    
    // MARK: - Quick Rule-Based Pre-filtering
    
    private func quickRuleBasedFilter(_ item: ProcessingItem) -> Bool? {
        let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = content.lowercased()
        
        // Filter out very short content (unless it's a URL or important)
        if content.count < 10 {
            if content.contains("http") || content.contains("@") {
                return true // Keep URLs and mentions
            }
            
            // Filter out very short casual responses
            let shortCasualResponses = ["ok", "thanks", "got it", "sure", "yep", "nope", "lol", "haha", "👍", "✅"]
            if shortCasualResponses.contains(where: { lowercased.contains($0) && content.count < 15 }) {
                return false
            }
        }
        
        // Always keep content from important sources
        switch item.source {
        case .email:
            return true // Always process emails
        case .meeting:
            return true // Always process meeting content
        default:
            break
        }
        
        // Filter out obvious system messages
        let systemPatterns = [
            "system notification", "auto-generated", "do not reply",
            "unsubscribe", "copyright", "privacy policy"
        ]
        if systemPatterns.contains(where: { lowercased.contains($0) }) {
            return false
        }
        
        // Keep content with obvious importance indicators
        let importanceIndicators = [
            "urgent", "asap", "deadline", "important", "critical",
            "action required", "please", "need", "help", "issue",
            "problem", "meeting", "call", "schedule", "reminder",
            "follow up", "commit", "promise", "will", "should",
            "todo", "task", "@", "?", "http", "www"
        ]
        if importanceIndicators.contains(where: { lowercased.contains($0) }) {
            return true
        }
        
        return nil // Needs more detailed analysis
    }
    
    // MARK: - AI-Based Filtering
    
    #if canImport(FoundationModels)
    private func filterWithAI(_ item: ProcessingItem, session: LanguageModelSession) async -> Bool {
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this content and determine if it's worth processing: "\(item.content)"
                
                Source: \(item.source)
                Priority: \(item.priority)
                Length: \(item.content.count) characters
                
                Consider:
                1. Does it contain actionable information?
                2. Is it business/work related?
                3. Does it require follow-up or response?
                4. Is it just casual conversation or small talk?
                5. Does it contain commitments, deadlines, or important info?
                
                Be conservative - when in doubt, mark as relevant.
                """,
                generating: FilteringAnalysisResult.self
            )
            
            logger.debug("AI filtering result: relevant=\(analysis.content.isRelevant), reason=\(analysis.content.reason)")
            return analysis.content.isRelevant
            
        } catch {
            logger.error("AI filtering failed: \(error.localizedDescription)")
            return detailedRuleBasedFilter(item) // Fallback to rules
        }
    }
    #endif
    
    // MARK: - Detailed Rule-Based Filtering
    
    private func detailedRuleBasedFilter(_ item: ProcessingItem) -> Bool {
        let content = item.content.lowercased()
        
        // Filter out weather discussions (unless business context)
        let weatherPatterns = [
            "weather", "rain", "sunny", "cloudy", "temperature", "degrees",
            "hot today", "cold today", "nice weather"
        ]
        if weatherPatterns.contains(where: { content.contains($0) }) &&
           !content.contains("meeting") && !content.contains("travel") {
            return false
        }
        
        // Filter out casual greetings and small talk
        let smallTalkPatterns = [
            "how are you", "how's it going", "what's up", "how was your weekend",
            "have a great day", "see you later", "talk to you soon",
            "good morning", "good afternoon", "good evening", "good night",
            "have a good", "enjoy your", "happy birthday", "congratulations"
        ]
        
        // Only filter if the ENTIRE content is just small talk
        let isOnlySmallTalk = smallTalkPatterns.contains { pattern in
            let contentWithoutPunctuation = content.replacingOccurrences(of: "[^a-zA-Z0-9\\s]", with: "", options: .regularExpression)
            return contentWithoutPunctuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   abs(contentWithoutPunctuation.count - pattern.count) < 10
        }
        
        if isOnlySmallTalk {
            return false
        }
        
        // Filter out social media fluff
        let socialMediaFluff = [
            "like this post", "share if you agree", "follow me",
            "hashtag", "instagram", "facebook", "twitter",
            "check out this meme", "lol", "lmao", "rofl"
        ]
        if socialMediaFluff.contains(where: { content.contains($0) }) &&
           !content.contains("business") && !content.contains("work") {
            return false
        }
        
        // Filter out entertainment content
        let entertainmentPatterns = [
            "movie", "netflix", "game", "sport", "football", "basketball",
            "tv show", "music", "concert", "party", "vacation"
        ]
        if entertainmentPatterns.contains(where: { content.contains($0) }) &&
           !containsBusinessContext(content) {
            return false
        }
        
        // Keep content with business/work indicators
        if containsBusinessContext(content) {
            return true
        }
        
        // Keep content with questions or requests
        if content.contains("?") || 
           content.contains("can you") ||
           content.contains("could you") ||
           content.contains("please") ||
           content.contains("help") {
            return true
        }
        
        // Keep content with time/date references (might be scheduling)
        let timePatterns = [
            "today", "tomorrow", "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday", "am", "pm", "o'clock",
            "minute", "hour", "day", "week", "month"
        ]
        if timePatterns.contains(where: { content.contains($0) }) {
            return true
        }
        
        // Default: keep content if we're unsure
        return true
    }
    
    private func containsBusinessContext(_ content: String) -> Bool {
        let businessKeywords = [
            "meeting", "project", "deadline", "client", "customer",
            "budget", "revenue", "task", "todo", "action item",
            "schedule", "appointment", "conference", "presentation",
            "report", "document", "file", "email", "urgent",
            "important", "asap", "follow up", "status", "update",
            "issue", "problem", "solution", "decision", "approval",
            "contract", "agreement", "proposal", "invoice",
            "team", "department", "manager", "director", "ceo",
            "commit", "promise", "will do", "responsible for"
        ]
        
        return businessKeywords.contains(where: { content.contains($0) })
    }
    
    // MARK: - Statistics and Monitoring
    
    func getFilteringStats() -> FilteringStats {
        return FilteringStats(
            totalProcessed: totalProcessed,
            filtered: filtered,
            passed: passed,
            filterRate: totalProcessed > 0 ? Double(filtered) / Double(totalProcessed) : 0.0
        )
    }
    
    func resetStats() {
        totalProcessed = 0
        filtered = 0
        passed = 0
        logger.info("Filtering statistics reset")
    }
    
    func logStats() {
        let stats = getFilteringStats()
        logger.info("Filtering Stats - Total: \(stats.totalProcessed), Filtered: \(stats.filtered), Passed: \(stats.passed), Filter Rate: \(String(format: "%.1f", stats.filterRate * 100))%")
    }
}

// MARK: - Supporting Data Structures

struct FilteringStats {
    let totalProcessed: Int
    let filtered: Int
    let passed: Int
    let filterRate: Double // Percentage of content filtered out
}

#if canImport(FoundationModels)
@Generable
struct FilteringAnalysisResult: Codable {
    @Guide(description: "Whether the content is relevant and should be processed further")
    let isRelevant: Bool
    
    @Guide(description: "Brief reason for the filtering decision")
    let reason: String
    
    @Guide(description: "Category of the content (business, personal, casual, spam, etc.)")
    let contentCategory: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
    
    @Guide(description: "Suggested tags if content is deemed relevant")
    let suggestedTags: [String]
}
#endif