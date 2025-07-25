import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Communication Analyzer Agent

@MainActor
class CommunicationAnalyzerAgent: BaseAIAgent {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "CommunicationAnalyzer")
    
    // Analysis patterns
    private let commitmentPatterns = [
        "i will", "i'll", "will get back", "will send", "will provide",
        "let me", "i can", "i'll check", "i'll look into", "will follow up",
        "promise to", "commit to", "planning to", "going to",
        "by [date]", "before [time]", "within [duration]"
    ]
    
    private let urgencyIndicators = [
        "urgent", "asap", "immediately", "critical", "important",
        "deadline", "by eod", "by end of day", "today", "now"
    ]
    
    init(communicationBus: AgentCommunicationBus? = nil) {
        super.init(
            specialization: .communicationAnalyzer,
            memorySize: 200,
            communicationBus: communicationBus
        )
    }
    
    override func processTask(_ task: AgentTask) async throws -> AgentResponse {
        isProcessing = true
        defer { isProcessing = false }
        
        logger.info("Analyzing communication: \(task.description)")
        
        guard let content = task.parameters["content"] as? String else {
            throw AgentError.invalidTask
        }
        
        // Analyze the communication
        let analysis = await analyzeCommunication(content, task: task)
        
        // Process detected commitments
        for commitment in analysis.commitments {
            await notifyCommitmentDetected(commitment)
        }
        
        // Process urgency
        if analysis.urgencyLevel == ProcessingPriority.urgent {
            await notifyUrgentAction(analysis)
        }
        
        return AgentResponse(
            taskId: task.id,
            status: .success,
            results: [
                "commitments": analysis.commitments,
                "participants": analysis.participants,
                "urgencyLevel": analysis.urgencyLevel.rawValue,
                "sentiment": analysis.sentiment,
                "actionItems": analysis.actionItems
            ],
            confidence: analysis.confidence,
            suggestedActions: generateSuggestedActions(from: analysis),
            error: nil
        )
    }
    
    // MARK: - Communication Analysis
    
    private func analyzeCommunication(_ content: String, task: AgentTask) async -> CommAnalysisResult {
        let lowercasedContent = content.lowercased()
        
        // Extract participants
        let participants = extractParticipants(from: content)
        
        // Detect commitments
        let commitments = await detectCommitments(in: content, participants: participants)
        
        // Analyze urgency
        let urgencyLevel = analyzeUrgency(in: lowercasedContent)
        
        // Extract action items
        let actionItems = extractActionItems(from: content)
        
        // Analyze sentiment
        let sentiment = analyzeSentiment(content)
        
        // Calculate confidence
        let confidence = calculateAnalysisConfidence(
            commitments: commitments,
            urgency: urgencyLevel,
            actionItems: actionItems
        )
        
        // Store in memory
        memory.store(MemoryItem(
            content: content,
            source: task.parameters["source"] as? ContentSource ?? .manual,
            tags: generateTags(from: commitments, urgency: urgencyLevel),
            timestamp: Date(),
            importance: urgencyLevel == .urgent ? 0.9 : 0.5
        ))
        
        return CommAnalysisResult(
            commitments: commitments,
            participants: participants,
            urgencyLevel: urgencyLevel,
            sentiment: sentiment,
            actionItems: actionItems,
            confidence: confidence
        )
    }
    
    private func detectCommitments(in content: String, participants: [String]) async -> [CommitmentInfo] {
        var commitments: [CommitmentInfo] = []
        
        #if canImport(FoundationModels)
        // Use Foundation Models for sophisticated commitment detection
        do {
            let prompt = """
            Analyze this communication for commitments and promises:
            
            Content: \(content)
            
            Identify any commitments, promises, or statements of intent. For each commitment, extract:
            1. What is being committed to
            2. Who is making the commitment
            3. Any mentioned deadline or timeframe
            4. The commitment's importance/urgency
            """
            
            let analysis = try await queryLanguageModel(prompt)
            
            // Parse the analysis to extract commitments
            commitments = parseCommitmentAnalysis(analysis, participants: participants)
        } catch {
            logger.error("Language model analysis failed: \(error)")
            // Fall back to pattern matching
            commitments = detectCommitmentsUsingPatterns(content, participants: participants)
        }
        #else
        // Use pattern matching
        commitments = detectCommitmentsUsingPatterns(content, participants: participants)
        #endif
        
        return commitments
    }
    
    private func detectCommitmentsUsingPatterns(_ content: String, participants: [String]) -> [CommitmentInfo] {
        var commitments: [CommitmentInfo] = []
        let sentences = content.components(separatedBy: .newlines)
        
        for sentence in sentences {
            let lowercased = sentence.lowercased()
            
            for pattern in commitmentPatterns {
                if lowercased.contains(pattern) {
                    let commitment = CommitmentInfo(
                        commitmentId: UUID(),
                        description: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        participants: participants,
                        deadline: extractDeadline(from: sentence),
                        source: .manual,
                        confidence: 0.7
                    )
                    commitments.append(commitment)
                    break
                }
            }
        }
        
        return commitments
    }
    
    private func extractParticipants(from content: String) -> [String] {
        var participants: [String] = []
        
        // Look for @mentions
        let mentionPattern = "@[a-zA-Z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: mentionPattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    let mention = String(content[range]).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    participants.append(mention)
                }
            }
        }
        
        // Look for email addresses
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    participants.append(String(content[range]))
                }
            }
        }
        
        // Look for names in "To:", "From:", "CC:" fields
        let fieldPatterns = ["To:", "From:", "CC:", "Cc:"]
        for pattern in fieldPatterns {
            if let range = content.range(of: pattern) {
                let afterPattern = content[range.upperBound...]
                if let endRange = afterPattern.firstIndex(of: "\n") {
                    let names = String(afterPattern[..<endRange])
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    participants.append(contentsOf: names.map { String($0) })
                }
            }
        }
        
        return Array(Set(participants)) // Remove duplicates
    }
    
    private func analyzeUrgency(in content: String) -> ProcessingPriority {
        var urgencyScore = 0
        
        for indicator in urgencyIndicators {
            if content.contains(indicator) {
                urgencyScore += 1
            }
        }
        
        // Check for time-related urgency
        let timePatterns = ["today", "tomorrow", "eod", "end of day", "asap", "immediately"]
        for pattern in timePatterns {
            if content.contains(pattern) {
                urgencyScore += 2
            }
        }
        
        // Map score to priority
        switch urgencyScore {
        case 0...1:
            return .low
        case 2...3:
            return .medium
        case 4...5:
            return .high
        default:
            return .urgent
        }
    }
    
    private func extractActionItems(from content: String) -> [String] {
        var actionItems: [String] = []
        
        // Look for bullet points or numbered lists
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for bullet points
            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let item = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    actionItems.append(String(item))
                }
            }
            
            // Check for numbered items
            if let firstChar = trimmed.first, firstChar.isNumber {
                if trimmed.dropFirst().hasPrefix(".") || trimmed.dropFirst().hasPrefix(")") {
                    let item = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty {
                        actionItems.append(String(item))
                    }
                }
            }
            
            // Check for action keywords
            let actionKeywords = ["need to", "should", "must", "have to", "required to"]
            for keyword in actionKeywords {
                if trimmed.lowercased().contains(keyword) {
                    actionItems.append(trimmed)
                    break
                }
            }
        }
        
        return actionItems
    }
    
    private func analyzeSentiment(_ content: String) -> String {
        // Simple sentiment analysis
        let positiveWords = ["great", "excellent", "good", "thanks", "appreciate", "happy", "pleased"]
        let negativeWords = ["problem", "issue", "concern", "worried", "frustrated", "disappointed", "urgent"]
        
        var positiveCount = 0
        var negativeCount = 0
        
        let lowercased = content.lowercased()
        for word in positiveWords {
            if lowercased.contains(word) {
                positiveCount += 1
            }
        }
        
        for word in negativeWords {
            if lowercased.contains(word) {
                negativeCount += 1
            }
        }
        
        if positiveCount > negativeCount {
            return "positive"
        } else if negativeCount > positiveCount {
            return "negative"
        } else {
            return "neutral"
        }
    }
    
    private func extractDeadline(from text: String) -> Date? {
        // Simple deadline extraction
        let calendar = Calendar.current
        let now = Date()
        
        let lowercased = text.lowercased()
        
        if lowercased.contains("today") || lowercased.contains("eod") {
            return calendar.dateInterval(of: .day, for: now)?.end
        } else if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        } else if lowercased.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }
        
        // Look for specific dates
        let datePattern = "\\d{1,2}/\\d{1,2}/\\d{2,4}"
        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let match = matches.first,
               let range = Range(match.range, in: text) {
                let dateString = String(text[range])
                let formatter = DateFormatter()
                formatter.dateFormat = "MM/dd/yyyy"
                return formatter.date(from: dateString)
            }
        }
        
        return nil
    }
    
    private func calculateAnalysisConfidence(
        commitments: [CommitmentInfo],
        urgency: ProcessingPriority,
        actionItems: [String]
    ) -> Double {
        var confidence = 0.5 // Base confidence
        
        if !commitments.isEmpty {
            confidence += 0.2
        }
        
        if urgency == .urgent || urgency == .high {
            confidence += 0.2
        }
        
        if !actionItems.isEmpty {
            confidence += 0.1
        }
        
        return min(confidence, 1.0)
    }
    
    private func generateTags(from commitments: [CommitmentInfo], urgency: ProcessingPriority) -> [ContentTag] {
        var tags: [ContentTag] = [.communication]
        
        if !commitments.isEmpty {
            tags.append(.commitment)
        }
        
        if urgency == .urgent {
            tags.append(.urgent_action)
        }
        
        if urgency == .high || urgency == .urgent {
            tags.append(.followup_required)
        }
        
        return tags
    }
    
    private func generateSuggestedActions(from analysis: CommAnalysisResult) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []
        
        // Suggest reminder creation for commitments
        for commitment in analysis.commitments {
            actions.append(SuggestedAction(
                description: "Create reminder for: \(commitment.description)",
                targetAgent: .reminderManager,
                priority: analysis.urgencyLevel,
                parameters: ["commitment": commitment]
            ))
        }
        
        // Suggest follow-up tracking
        if analysis.urgencyLevel == ProcessingPriority.high || analysis.urgencyLevel == ProcessingPriority.urgent {
            actions.append(SuggestedAction(
                description: "Track follow-up for urgent communication",
                targetAgent: .followupTracking,
                priority: analysis.urgencyLevel,
                parameters: ["analysis": analysis]
            ))
        }
        
        return actions
    }
    
    // MARK: - Notifications
    
    private func notifyCommitmentDetected(_ commitment: CommitmentInfo) async {
        guard let bus = communicationBus else { return }
        
        let message = AgentMessage(
            type: .commitmentDetected,
            from: specialization,
            content: .commitment(commitment),
            priority: commitment.deadline != nil ? .high : .normal
        )
        
        await bus.broadcast(message)
    }
    
    private func notifyUrgentAction(_ analysis: CommAnalysisResult) async {
        guard let bus = communicationBus else { return }
        
        let message = AgentMessage(
            type: .urgentNotification,
            from: specialization,
            content: .text("Urgent communication detected with \(analysis.commitments.count) commitments"),
            priority: .urgent
        )
        
        await bus.broadcast(message)
    }
    
    // MARK: - Helper Methods
    
    private func parseCommitmentAnalysis(_ analysis: String, participants: [String]) -> [CommitmentInfo] {
        // This would parse the language model's response
        // For now, returning empty array as placeholder
        return []
    }
}

// MARK: - Communication Analysis Model

struct CommAnalysisResult {
    let commitments: [CommitmentInfo]
    let participants: [String]
    let urgencyLevel: ProcessingPriority
    let sentiment: String
    let actionItems: [String]
    let confidence: Double
}