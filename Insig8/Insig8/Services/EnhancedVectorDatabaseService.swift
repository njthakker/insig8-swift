import SwiftUI
import Combine
import NaturalLanguage
import Accelerate
import OSLog

// MARK: - Enhanced Vector Database Service with Tagging
class EnhancedVectorDatabaseService: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "EnhancedVectorDB")
    private let embeddingModel = NLEmbedding.wordEmbedding(for: .english)
    
    // Vector storage with tags
    private var taggedVectors: [TaggedVector] = []
    
    // Configuration
    private let maxVectors = 10000
    private let similarityThreshold: Float = 0.6
    private let embeddingDimensions = 300
    
    init() {
        loadVectorDatabase()
    }
    
    // MARK: - Storage Methods
    
    func storeContent(_ content: String, tags: [ContentTag], source: ContentSource, timestamp: Date = Date()) async {
        guard content.count > 10 else { return } // Skip very short content
        
        if let embedding = await generateEmbedding(for: content) {
            let vector = TaggedVector(
                id: UUID(),
                content: content,
                source: source,
                tags: tags,
                embedding: embedding,
                timestamp: timestamp,
                accessCount: 0,
                lastAccessed: timestamp
            )
            
            await MainActor.run {
                taggedVectors.append(vector)
                
                // Cleanup old vectors if needed
                if taggedVectors.count > maxVectors {
                    // Remove oldest, least accessed vectors
                    taggedVectors.sort { 
                        if $0.accessCount != $1.accessCount {
                            return $0.accessCount < $1.accessCount
                        }
                        return $0.timestamp < $1.timestamp
                    }
                    taggedVectors = Array(taggedVectors.suffix(maxVectors))
                }
                
                saveVectorDatabase()
                logger.info("Stored content with tags: \\(tags.map { $0.rawValue }.joined(separator: \", \"))")
            }
        }
    }
    
    // MARK: - Semantic Search with Tag Filtering
    
    func semanticSearch(query: String, tags: [ContentTag]? = nil, limit: Int = 10) async -> [TaggedSearchResult] {
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            return []
        }
        
        var candidateVectors = taggedVectors
        
        // Filter by tags if specified
        if let tags = tags, !tags.isEmpty {
            candidateVectors = candidateVectors.filter { vector in
                !Set(vector.tags).intersection(Set(tags)).isEmpty
            }
        }
        
        var results: [(TaggedVector, Float)] = []
        
        for vector in candidateVectors {
            let similarity = cosineSimilarity(queryEmbedding, vector.embedding)
            if similarity >= similarityThreshold {
                results.append((vector, similarity))
            }
        }
        
        // Sort by similarity and recency
        results.sort { (a, b) in
            let similarityDiff = a.1 - b.1
            if abs(similarityDiff) < 0.1 { // Similar scores, prefer recent
                return a.0.timestamp > b.0.timestamp
            }
            return similarityDiff > 0
        }
        
        // Update access counts
        await MainActor.run {
            for (vector, _) in Array(results.prefix(limit)) {
                if let index = taggedVectors.firstIndex(where: { $0.id == vector.id }) {
                    taggedVectors[index].accessCount += 1
                    taggedVectors[index].lastAccessed = Date()
                }
            }
        }
        
        return Array(results.prefix(limit)).map { (vector, similarity) in
            TaggedSearchResult(
                id: vector.id,
                content: vector.content,
                source: vector.source,
                tags: vector.tags,
                similarity: similarity,
                timestamp: vector.timestamp
            )
        }
    }
    
    // MARK: - Advanced Search Methods
    
    func searchByTag(_ tag: ContentTag, limit: Int = 20) async -> [TaggedSearchResult] {
        let filteredVectors = taggedVectors
            .filter { $0.tags.contains(tag) }
            .sorted { $0.timestamp > $1.timestamp }
        
        return Array(filteredVectors.prefix(limit)).map { vector in
            TaggedSearchResult(
                id: vector.id,
                content: vector.content,
                source: vector.source,
                tags: vector.tags,
                similarity: 1.0, // Perfect tag match
                timestamp: vector.timestamp
            )
        }
    }
    
    func searchBySource(_ source: ContentSource, limit: Int = 20) async -> [TaggedSearchResult] {
        let filteredVectors = taggedVectors
            .filter { areSourcesEqual($0.source, source) }
            .sorted { $0.timestamp > $1.timestamp }
        
        return Array(filteredVectors.prefix(limit)).map { vector in
            TaggedSearchResult(
                id: vector.id,
                content: vector.content,
                source: vector.source,
                tags: vector.tags,
                similarity: 1.0, // Perfect source match
                timestamp: vector.timestamp
            )
        }
    }
    
    func searchByTimeRange(from startDate: Date, to endDate: Date, limit: Int = 50) async -> [TaggedSearchResult] {
        let filteredVectors = taggedVectors
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp > $1.timestamp }
        
        return Array(filteredVectors.prefix(limit)).map { vector in
            TaggedSearchResult(
                id: vector.id,
                content: vector.content,
                source: vector.source,
                tags: vector.tags,
                similarity: 1.0,
                timestamp: vector.timestamp
            )
        }
    }
    
    // Natural language search combining multiple criteria
    func intelligentSearch(query: String, limit: Int = 10) async -> [TaggedSearchResult] {
        // Parse query for different search criteria
        let lowercasedQuery = query.lowercased()
        var tags: [ContentTag] = []
        var timeFilter: Date?
        
        // Extract tag hints from query
        if lowercasedQuery.contains("urgent") || lowercasedQuery.contains("important") {
            tags.append(.urgent_action)
        }
        if lowercasedQuery.contains("email") {
            tags.append(.email_thread)
        }
        if lowercasedQuery.contains("meeting") {
            tags.append(.meeting_notes)
        }
        if lowercasedQuery.contains("commitment") || lowercasedQuery.contains("promise") {
            tags.append(.commitment)
        }
        if lowercasedQuery.contains("follow up") || lowercasedQuery.contains("followup") {
            tags.append(.followup_required)
        }
        
        // Extract time hints
        if lowercasedQuery.contains("today") {
            timeFilter = Calendar.current.startOfDay(for: Date())
        } else if lowercasedQuery.contains("yesterday") {
            timeFilter = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        } else if lowercasedQuery.contains("this week") {
            timeFilter = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
        }
        
        // Perform semantic search with filters
        var results = await semanticSearch(query: query, tags: tags.isEmpty ? nil : tags, limit: limit * 2)
        
        // Apply time filter if specified
        if let timeFilter = timeFilter {
            results = results.filter { $0.timestamp >= timeFilter }
        }
        
        return Array(results.prefix(limit))
    }
    
    // MARK: - Analytics and Statistics
    
    func getTagStatistics() -> [ContentTag: Int] {
        var tagCounts: [ContentTag: Int] = [:]
        
        for vector in taggedVectors {
            for tag in vector.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        
        return tagCounts
    }
    
    func getSourceStatistics() -> [String: Int] {
        var sourceCounts: [String: Int] = [:]
        
        for vector in taggedVectors {
            let sourceKey = getSourceKey(vector.source)
            sourceCounts[sourceKey, default: 0] += 1
        }
        
        return sourceCounts
    }
    
    func getMostAccessedContent(limit: Int = 10) -> [TaggedSearchResult] {
        let sortedVectors = taggedVectors
            .sorted { $0.accessCount > $1.accessCount }
        
        return Array(sortedVectors.prefix(limit)).map { vector in
            TaggedSearchResult(
                id: vector.id,
                content: vector.content,
                source: vector.source,
                tags: vector.tags,
                similarity: 1.0,
                timestamp: vector.timestamp
            )
        }
    }
    
    // MARK: - Utility Methods
    
    private func generateEmbedding(for text: String) async -> [Float]? {
        guard let embedding = embeddingModel else {
            logger.error("Word embedding model not available")
            return nil
        }
        
        let cleanText = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        
        guard !cleanText.isEmpty else { return nil }
        
        if let vector = embedding.vector(for: cleanText) {
            return vector.map { Float($0) }
        }
        
        // Fallback: word-by-word embedding averaging
        let words = cleanText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        var averageVector = Array(repeating: Float(0.0), count: embeddingDimensions)
        var validWords = 0
        
        for word in words {
            if let wordVector = embedding.vector(for: word) {
                for i in 0..<min(wordVector.count, embeddingDimensions) {
                    averageVector[i] += Float(wordVector[i])
                }
                validWords += 1
            }
        }
        
        if validWords > 0 {
            for i in 0..<embeddingDimensions {
                averageVector[i] /= Float(validWords)
            }
            return averageVector
        }
        
        return nil
    }
    
    private func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        guard vectorA.count == vectorB.count else { return 0.0 }
        
        let dotProduct = zip(vectorA, vectorB).map(*).reduce(0, +)
        let magnitudeA = sqrt(vectorA.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(vectorB.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    private func areSourcesEqual(_ source1: ContentSource, _ source2: ContentSource) -> Bool {
        return getSourceKey(source1) == getSourceKey(source2)
    }
    
    private func getSourceKey(_ source: ContentSource) -> String {
        switch source {
        case .clipboard:
            return "clipboard"
        case .screenCapture(let app):
            return "screen:\(app)"
        case .email:
            return "email"
        case .browser:
            return "browser"
        case .meeting:
            return "meeting"
        case .manual:
            return "manual"
        }
    }
    
    // MARK: - Persistence
    
    private func saveVectorDatabase() {
        let encoder = JSONEncoder()
        
        // Save only essential data (without embeddings to save space)
        let vectorData = taggedVectors.map { vector in
            TaggedVectorData(
                id: vector.id,
                content: vector.content,
                source: vector.source,
                tags: vector.tags,
                timestamp: vector.timestamp,
                accessCount: vector.accessCount,
                lastAccessed: vector.lastAccessed
            )
        }
        
        if let data = try? encoder.encode(vectorData) {
            UserDefaults.standard.set(data, forKey: "EnhancedVectorDatabase")
        }
    }
    
    private func loadVectorDatabase() {
        let decoder = JSONDecoder()
        
        if let data = UserDefaults.standard.data(forKey: "EnhancedVectorDatabase"),
           let vectorData = try? decoder.decode([TaggedVectorData].self, from: data) {
            
            // Reconstruct vectors (embeddings will be regenerated on demand)
            self.taggedVectors = vectorData.map { data in
                TaggedVector(
                    id: data.id,
                    content: data.content,
                    source: data.source,
                    tags: data.tags,
                    embedding: [], // Will be regenerated on first use
                    timestamp: data.timestamp,
                    accessCount: data.accessCount,
                    lastAccessed: data.lastAccessed
                )
            }
            
            logger.info("Loaded enhanced vector database: \(self.taggedVectors.count) vectors")
        }
    }
    
    var vectorCount: Int {
        taggedVectors.count
    }
}

// MARK: - Data Models

struct TaggedVector {
    let id: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    var embedding: [Float]
    let timestamp: Date
    var accessCount: Int
    var lastAccessed: Date
}

struct TaggedVectorData: Codable {
    let id: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let timestamp: Date
    let accessCount: Int
    let lastAccessed: Date
}

struct TaggedSearchResult {
    let id: UUID
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let similarity: Float
    let timestamp: Date
}