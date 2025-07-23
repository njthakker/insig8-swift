import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Context Correlation Agent
class ContextCorrelationAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "ContextAgent")
    weak var delegate: AIAgentDelegate?
    
    #if canImport(FoundationModels)
    private var aiSession: LanguageModelSession?
    #endif
    
    // Context tracking
    private var recentContexts: [ContextItem] = []
    private var correlationMap: [UUID: [UUID]] = [:]
    
    init() {
        setupAISession()
    }
    
    private func setupAISession() {
        #if canImport(FoundationModels)
        aiSession = LanguageModelSession {
            """
            You are a context correlation AI. Your job is to identify relationships between different pieces of content across time and sources.
            
            Look for correlations such as:
            - Same people mentioned across different communications
            - Related projects or topics discussed in different contexts
            - Follow-up conversations referencing earlier content
            - Action items that relate to previous commitments
            - Email threads that connect to meeting discussions
            - Screen captures that relate to email conversations
            
            Help build a connected understanding of user's activities and communications.
            """
        }
        #endif
    }
    
    func correlateContext(_ item: ProcessingItem, tags: [ContentTag]) async {
        logger.info("Correlating context for: \(item.source)")
        
        // Create context item for tracking
        let contextItem = ContextItem(
            id: item.id,
            content: item.content,
            source: item.source,
            tags: tags,
            timestamp: item.timestamp,
            extractedEntities: extractEntities(from: item.content)
        )
        
        // Add to recent contexts (keep last 50 items)
        recentContexts.append(contextItem)
        if recentContexts.count > 50 {
            recentContexts.removeFirst()
        }
        
        // Find correlations with recent content
        let correlations = await findCorrelations(for: contextItem)
        
        if !correlations.isEmpty {
            correlationMap[item.id] = correlations.map { $0.id }
            
            // Create correlation task if significant
            if correlations.count >= 2 || correlations.contains(where: { isHighImportanceCorrelation($0, contextItem) }) {
                let correlationTask = createCorrelationTask(contextItem: contextItem, correlatedItems: correlations)
                delegate?.agentDidCreateTask(correlationTask)
            }
        }
    }
    
    private func findCorrelations(for item: ContextItem) async -> [ContextItem] {
        #if canImport(FoundationModels)
        if let session = aiSession, !session.isResponding {
            return await findCorrelationsWithAI(item, session: session)
        } else {
            return findCorrelationsWithRules(item)
        }
        #else
        return findCorrelationsWithRules(item)
        #endif
    }
    
    #if canImport(FoundationModels)
    private func findCorrelationsWithAI(_ item: ContextItem, session: LanguageModelSession) async -> [ContextItem] {
        // Get recent contexts for analysis
        let recentContextsText = recentContexts.suffix(10).map { context in
            "ID: \(context.id), Source: \(context.source), Content: \(String(context.content.prefix(100)))"
        }.joined(separator: "\n")
        
        do {
            let analysis = try await session.respond(
                to: """
                Analyze this new content for correlations with recent contexts:
                
                NEW CONTENT:
                Content: \(item.content)
                Source: \(item.source)
                Tags: \(item.tags.map { $0.rawValue }.joined(separator: ", "))
                
                RECENT CONTEXTS:
                \(recentContextsText)
                
                Find correlations based on:
                - Same people/names mentioned
                - Related topics or projects
                - Referenced earlier conversations
                - Connected action items
                - Related email threads
                
                Return the IDs of correlated items.
                """,
                generating: CorrelationAnalysisResult.self
            )
            
            let correlatedIds = analysis.content.correlatedItemIds.compactMap { UUID(uuidString: $0) }
            return recentContexts.filter { correlatedIds.contains($0.id) }
            
        } catch {
            logger.error("AI correlation analysis failed: \(error.localizedDescription)")
            return findCorrelationsWithRules(item)
        }
    }
    #endif
    
    private func findCorrelationsWithRules(_ item: ContextItem) -> [ContextItem] {
        var correlations: [ContextItem] = []
        
        // Look for correlations in recent contexts (last 20 items)
        for recentItem in recentContexts.suffix(20) {
            if recentItem.id == item.id { continue }
            
            var correlationScore = 0.0
            
            // Entity overlap (people, emails, etc.)
            let commonEntities = Set(item.extractedEntities.keys).intersection(Set(recentItem.extractedEntities.keys))
            correlationScore += Double(commonEntities.count) * 0.3
            
            // Source correlation (same app or communication thread)
            if areSourcesRelated(item.source, recentItem.source) {
                correlationScore += 0.4
            }
            
            // Time proximity (within last 2 hours)
            let timeDifference = abs(item.timestamp.timeIntervalSince(recentItem.timestamp))
            if timeDifference < 7200 { // 2 hours
                correlationScore += 0.2
            }
            
            // Tag correlation
            let commonTags = Set(item.tags).intersection(Set(recentItem.tags))
            correlationScore += Double(commonTags.count) * 0.1
            
            // Content similarity (simple keyword matching)
            correlationScore += calculateContentSimilarity(item.content, recentItem.content)
            
            // If correlation score is high enough, add to correlations
            if correlationScore >= 0.5 {
                correlations.append(recentItem)
            }
        }
        
        // Sort by correlation strength and return top 5
        return Array(correlations.prefix(5))
    }
    
    private func extractEntities(from content: String) -> [String: EntityType] {
        var entities: [String: EntityType] = [:]
        
        // Extract email addresses
        let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        if let emailRegex = emailRegex {
            let matches = emailRegex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    entities[String(content[range])] = .email
                }
            }
        }
        
        // Extract @mentions
        let mentionRegex = try? NSRegularExpression(pattern: "@[A-Za-z0-9_]+")
        if let mentionRegex = mentionRegex {
            let matches = mentionRegex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    entities[String(content[range])] = .mention
                }
            }
        }
        
        // Extract URLs
        let urlRegex = try? NSRegularExpression(pattern: "https?://[^\\s]+")
        if let urlRegex = urlRegex {
            let matches = urlRegex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    entities[String(content[range])] = .url
                }
            }
        }
        
        // Extract potential names (capitalized words, basic heuristic)
        let namePattern = "\\b[A-Z][a-z]+ [A-Z][a-z]+\\b"
        let nameRegex = try? NSRegularExpression(pattern: namePattern)
        if let nameRegex = nameRegex {
            let matches = nameRegex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    entities[String(content[range])] = .person
                }
            }
        }
        
        return entities
    }
    
    private func areSourcesRelated(_ source1: ContentSource, _ source2: ContentSource) -> Bool {
        switch (source1, source2) {
        case (.email, .email):
            return true
        case (.screenCapture(let app1), .screenCapture(let app2)):
            return app1 == app2
        case (.meeting, .screenCapture(let app)):
            return app.lowercased().contains("zoom") || app.lowercased().contains("teams") || app.lowercased().contains("meet")
        default:
            return false
        }
    }
    
    private func calculateContentSimilarity(_ content1: String, _ content2: String) -> Double {
        let words1 = Set(content1.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 })
        let words2 = Set(content2.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 })
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
    }
    
    private func isHighImportanceCorrelation(_ item1: ContextItem, _ item2: ContextItem) -> Bool {
        // Check if correlation involves high-priority content
        let highPriorityTags: Set<ContentTag> = [.urgent_action, .commitment, .deadline, .important]
        
        let item1HighPriority = !Set(item1.tags).intersection(highPriorityTags).isEmpty
        let item2HighPriority = !Set(item2.tags).intersection(highPriorityTags).isEmpty
        
        return item1HighPriority || item2HighPriority
    }
    
    private func createCorrelationTask(contextItem: ContextItem, correlatedItems: [ContextItem]) -> AITask {
        let correlationDescription = generateCorrelationDescription(contextItem: contextItem, correlatedItems: correlatedItems)
        
        return AITask(
            id: UUID(),
            description: correlationDescription,
            source: contextItem.source,
            tags: [.important, .communication] + contextItem.tags,
            priority: determineCorrelationPriority(contextItem: contextItem, correlatedItems: correlatedItems),
            status: .pending,
            dueDate: Date().addingTimeInterval(3600), // 1 hour to review
            createdDate: Date(),
            modifiedDate: Date(),
            relevanceScore: 0.9
        )
    }
    
    private func generateCorrelationDescription(contextItem: ContextItem, correlatedItems: [ContextItem]) -> String {
        let correlatedSources = correlatedItems.map { $0.source }.map { "\($0)" }.joined(separator: ", ")
        return "Connected activity detected: Recent \(contextItem.source) relates to \(correlatedSources). Review for context continuity."
    }
    
    private func determineCorrelationPriority(contextItem: ContextItem, correlatedItems: [ContextItem]) -> ProcessingPriority {
        let allItems = [contextItem] + correlatedItems
        let highPriorityTags: Set<ContentTag> = [.urgent_action, .commitment, .deadline]
        
        if allItems.contains(where: { !Set($0.tags).intersection(highPriorityTags).isEmpty }) {
            return .high
        } else {
            return .medium
        }
    }
    
    // Public method to get correlations for a specific item
    func getCorrelations(for itemId: UUID) -> [UUID] {
        return correlationMap[itemId] ?? []
    }
    
    // Public method to get context graph for visualization
    func getContextGraph() -> [ContextGraphNode] {
        return recentContexts.map { context in
            ContextGraphNode(
                id: context.id,
                content: String(context.content.prefix(100)),
                source: context.source,
                tags: context.tags,
                timestamp: context.timestamp,
                correlations: correlationMap[context.id] ?? []
            )
        }
    }
}

// MARK: - Supporting Data Structures

struct ContextItem {
    let id: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let timestamp: Date
    let extractedEntities: [String: EntityType]
}

enum EntityType: String {
    case person = "person"
    case email = "email"
    case mention = "mention"
    case url = "url"
    case project = "project"
    case company = "company"
}

struct ContextGraphNode {
    let id: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let timestamp: Date
    let correlations: [UUID]
}

#if canImport(FoundationModels)
@Generable
struct CorrelationAnalysisResult: Codable {
    @Guide(description: "List of item IDs that correlate with the new content")
    let correlatedItemIds: [String]
    
    @Guide(description: "Brief explanation of the correlations found")
    let correlationReason: String
    
    @Guide(description: "Strength of correlation from 0.0 to 1.0")
    let correlationStrength: Double
    
    @Guide(description: "Type of correlation (person, topic, project, thread, etc.)")
    let correlationType: String
}
#endif