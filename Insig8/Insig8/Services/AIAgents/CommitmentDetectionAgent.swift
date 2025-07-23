import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Commitment Detection Agent
class CommitmentDetectionAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "CommitmentAgent")
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
            You are a commitment detection AI. Analyze text to identify promises, commitments, and obligations made by the user.
            
            Look for patterns like:
            - "I will..."
            - "I'll get back to you..."
            - "Let me check and respond..."
            - "I'll look into this..."
            - "I'll send you..."
            - "I promise to..."
            - "I'll have it ready by..."
            
            Extract the commitment, identify the recipient, estimate deadline, and assess urgency.
            """
        }
        #endif
    }
    
    func processCommitment(_ item: ProcessingItem, tags: [ContentTag]) async {
        logger.info("Processing commitment for content: \(item.source)")
        
        #if canImport(FoundationModels)
        if let session = aiSession, !session.isResponding {
            await processWithAI(item, session: session)
        } else {
            await processWithRules(item)
        }
        #else
        await processWithRules(item)
        #endif
    }
    
    #if canImport(FoundationModels)
    private func processWithAI(_ item: ProcessingItem, session: LanguageModelSession) async {
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this content for commitments: "\(item.content)"
                
                Source: \(item.source)
                Timestamp: \(item.timestamp)
                
                Identify:
                1. What commitment was made?
                2. Who is the recipient?
                3. When should it be completed?
                4. What is the urgency level?
                5. What specific action is required?
                """,
                generating: CommitmentAnalysisResult.self
            )
            
            if analysis.content.hasCommitment {
                let task = createCommitmentTask(from: analysis.content, item: item)
                delegate?.agentDidCreateTask(task)
            }
            
        } catch {
            logger.error("AI commitment analysis failed: \(error.localizedDescription)")
            await processWithRules(item)
        }
    }
    #endif
    
    private func processWithRules(_ item: ProcessingItem) async {
        let content = item.content.lowercased()
        
        // Rule-based commitment detection
        let commitmentPatterns = [
            "i will", "i'll", "let me", "i promise", "i'll get back",
            "i'll check", "i'll send", "i'll look into", "i'll have it ready"
        ]
        
        var foundCommitments: [String] = []
        
        for pattern in commitmentPatterns {
            if content.contains(pattern) {
                // Extract the full sentence containing the commitment
                let sentences = item.content.components(separatedBy: ".")
                for sentence in sentences {
                    if sentence.lowercased().contains(pattern) {
                        foundCommitments.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
        
        if !foundCommitments.isEmpty {
            let task = AITask(
                id: UUID(),
                description: foundCommitments.joined(separator: " | "),
                source: item.source,
                tags: [.commitment, .followup_required],
                priority: .medium,
                status: .pending,
                dueDate: estimateDueDate(from: item.content),
                createdDate: Date(),
                modifiedDate: Date(),
                relevanceScore: 0.7
            )
            
            delegate?.agentDidCreateTask(task)
        }
    }
    
    private func estimateDueDate(from content: String) -> Date? {
        let lowercased = content.lowercased()
        let now = Date()
        
        if lowercased.contains("today") || lowercased.contains("asap") {
            return Calendar.current.date(byAdding: .hour, value: 4, to: now)
        } else if lowercased.contains("tomorrow") {
            return Calendar.current.date(byAdding: .day, value: 1, to: now)
        } else if lowercased.contains("next week") {
            return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)
        } else if lowercased.contains("friday") {
            return Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end
        } else {
            // Default: 3 hours from now
            return Calendar.current.date(byAdding: .hour, value: 3, to: now)
        }
    }
    
    #if canImport(FoundationModels)
    private func createCommitmentTask(from analysis: CommitmentAnalysisResult, item: ProcessingItem) -> AITask {
        return AITask(
            id: UUID(),
            description: analysis.commitmentText,
            source: item.source,
            tags: [.commitment, .followup_required],
            priority: ProcessingPriority(rawValue: analysis.urgencyLevel) ?? .medium,
            status: .pending,
            dueDate: parseDateString(analysis.estimatedDeadline),
            createdDate: Date(),
            modifiedDate: Date(),
            relevanceScore: Float(analysis.confidence)
        )
    }
    
    private func parseDateString(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Handle natural language dates
        return estimateDueDate(from: dateString)
    }
    #endif
}

#if canImport(FoundationModels)
@Generable
struct CommitmentAnalysisResult: Codable {
    @Guide(description: "Whether a commitment was found in the text")
    let hasCommitment: Bool
    
    @Guide(description: "The commitment text extracted from the content")
    let commitmentText: String
    
    @Guide(description: "Who the commitment is made to")
    let recipient: String
    
    @Guide(description: "Estimated deadline for the commitment (ISO8601 or natural language)")
    let estimatedDeadline: String?
    
    @Guide(description: "Urgency level: 1=low, 2=medium, 3=high, 4=urgent")
    let urgencyLevel: Int
    
    @Guide(description: "Specific action required to fulfill the commitment")
    let actionRequired: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    let confidence: Double
}
#endif