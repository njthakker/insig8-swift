import FoundationModels
import OSLog

struct MeetingSummary: Codable {
    var title: String
    var attendees: [String]
    var keyDecisions: [String]
    var actionItems: [String]
    
    // Legacy fields for backward compatibility with existing UI
    var duration: String = "00:00"
    var wordCount: Int = 0
    var confidence: Float = 0.8
    var keyTopics: [String] = [] // UI compatibility
}

final class MeetingLLMService {
    private let session = LanguageModelSession()
    private let logger  = Logger(subsystem: "com.insig8", category: "LLM")

    func summarize(_ text: String) async throws -> MeetingSummary {
        guard !text.isEmpty else {
            throw NSError(domain: "MeetingLLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty transcript provided"])
        }
        
        // For now, use a basic summary until FoundationModels are stable
        logger.info("Generating basic summary from transcript")
        
        // Extract key information from the text
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        
        // Simple key decision extraction
        let decisionKeywords = ["decided", "agreed", "concluded", "resolved"]
        let keyDecisions = lines.filter { line in
            decisionKeywords.contains { line.lowercased().contains($0) }
        }.prefix(3).map { String($0) }
        
        // Simple action item extraction
        let actionKeywords = ["will", "should", "need to", "action", "todo"]
        let actionItems = lines.filter { line in
            actionKeywords.contains { line.lowercased().contains($0) }
        }.prefix(5).map { String($0) }
        
        let summary = MeetingSummary(
            title: "Meeting Summary",
            attendees: [],
            keyDecisions: Array(keyDecisions),
            actionItems: Array(actionItems),
            duration: "00:00", // Will be populated by MeetingService
            wordCount: words.count,
            confidence: 0.8,
            keyTopics: Array(keyDecisions) // Use decisions as topics for UI compatibility
        )
        
        logger.info("Summary generated with \(summary.keyDecisions.count) decisions and \(summary.actionItems.count) action items")
        return summary
    }
}