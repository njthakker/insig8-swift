import SwiftUI
import Combine
import NaturalLanguage
import Accelerate
import OSLog

// MARK: - Vector Database Service for Semantic Search
class VectorDatabaseService: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ai", category: "VectorDatabase")
    private let embeddingModel = NLEmbedding.wordEmbedding(for: .english)
    
    // Vector storage
    private var urlVectors: [URLVector] = []
    private var contentVectors: [ContentVector] = []
    
    // Configuration
    private let maxVectors = 10000
    private let similarityThreshold: Float = 0.7
    private let embeddingDimensions = 300 // Word2Vec dimensions
    
    init() {
        loadVectorDatabase()
    }
    
    // MARK: - URL Vector Management
    
    func addURL(_ url: String, title: String?, description: String?, timestamp: Date = Date()) {
        let content = [title, description, url].compactMap { $0 }.joined(separator: " ")
        
        Task {
            if let embedding = await generateEmbedding(for: content) {
                let vector = URLVector(
                    id: UUID(),
                    url: url,
                    title: title ?? "Unknown",
                    description: description ?? "",
                    content: content,
                    embedding: embedding,
                    timestamp: timestamp
                )
                
                urlVectors.append(vector)
                
                // Cleanup old vectors if needed
                if urlVectors.count > maxVectors {
                    urlVectors = Array(urlVectors.suffix(maxVectors))
                }
                
                saveVectorDatabase()
                logger.info("Added URL vector: \(url)")
            }
        }
    }
    
    func addClipboardContent(_ content: String, type: ContentType, timestamp: Date = Date()) {
        // Only store URLs and meaningful text in vector database
        guard type == .url || (type == .text && content.count > 50) else { return }
        
        Task {
            if let embedding = await generateEmbedding(for: content) {
                let vector = ContentVector(
                    id: UUID(),
                    content: content,
                    type: type,
                    embedding: embedding,
                    timestamp: timestamp
                )
                
                contentVectors.append(vector)
                
                // Cleanup old vectors if needed
                if contentVectors.count > maxVectors {
                    contentVectors = Array(contentVectors.suffix(maxVectors))
                }
                
                saveVectorDatabase()
                logger.info("Added content vector: \(type.rawValue)")
            }
        }
    }
    
    // MARK: - Semantic Search
    
    func searchURLs(query: String, limit: Int = 10) async -> [URLSearchResult] {
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            return []
        }
        
        var results: [(URLVector, Float)] = []
        
        for urlVector in urlVectors {
            let similarity = cosineSimilarity(queryEmbedding, urlVector.embedding)
            if similarity >= similarityThreshold {
                results.append((urlVector, similarity))
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
        
        return Array(results.prefix(limit)).map { (vector, similarity) in
            URLSearchResult(
                url: vector.url,
                title: vector.title,
                description: vector.description,
                similarity: similarity,
                timestamp: vector.timestamp
            )
        }
    }
    
    func searchContent(query: String, limit: Int = 10) async -> [ContentSearchResult] {
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            return []
        }
        
        var results: [(ContentVector, Float)] = []
        
        for contentVector in contentVectors {
            let similarity = cosineSimilarity(queryEmbedding, contentVector.embedding)
            if similarity >= similarityThreshold {
                results.append((contentVector, similarity))
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
        
        return Array(results.prefix(limit)).map { (vector, similarity) in
            ContentSearchResult(
                content: vector.content,
                type: vector.type,
                similarity: similarity,
                timestamp: vector.timestamp
            )
        }
    }
    
    // Combined semantic search for command palette
    func searchAll(query: String, limit: Int = 5) async -> [SemanticSearchResult] {
        let urlResults = await searchURLs(query: query, limit: limit)
        let contentResults = await searchContent(query: query, limit: limit)
        
        var allResults: [SemanticSearchResult] = []
        
        // Convert URL results
        allResults.append(contentsOf: urlResults.map { result in
            SemanticSearchResult(
                title: result.title,
                content: result.url,
                type: .url,
                similarity: result.similarity,
                timestamp: result.timestamp,
                url: result.url
            )
        })
        
        // Convert content results
        allResults.append(contentsOf: contentResults.map { result in
            SemanticSearchResult(
                title: "Clipboard: \\(result.type.rawValue.capitalized)",
                content: String(result.content.prefix(100)) + (result.content.count > 100 ? "..." : ""),
                type: result.type,
                similarity: result.similarity,
                timestamp: result.timestamp,
                url: nil
            )
        })
        
        // Sort by similarity
        allResults.sort { $0.similarity > $1.similarity }
        
        return Array(allResults.prefix(limit))
    }
    
    // MARK: - Embedding Generation
    
    func generateEmbedding(for text: String) async -> [Float]? {
        guard let embedding = embeddingModel else {
            logger.error("Word embedding model not available")
            return nil
        }
        
        // Clean and prepare text
        let cleanText = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        
        guard !cleanText.isEmpty else { return nil }
        
        // Generate embedding using NLEmbedding
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
    
    // MARK: - Similarity Calculation
    
    private func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        guard vectorA.count == vectorB.count else { return 0.0 }
        
        let dotProduct = zip(vectorA, vectorB).map(*).reduce(0, +)
        let magnitudeA = sqrt(vectorA.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(vectorB.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    // MARK: - Persistence
    
    private func saveVectorDatabase() {
        let encoder = JSONEncoder()
        
        if let urlData = try? encoder.encode(urlVectors) {
            UserDefaults.standard.set(urlData, forKey: "URLVectors")
        }
        
        if let contentData = try? encoder.encode(contentVectors) {
            UserDefaults.standard.set(contentData, forKey: "ContentVectors")
        }
    }
    
    private func loadVectorDatabase() {
        let decoder = JSONDecoder()
        
        if let urlData = UserDefaults.standard.data(forKey: "URLVectors"),
           let loadedURLVectors = try? decoder.decode([URLVector].self, from: urlData) {
            urlVectors = loadedURLVectors
        }
        
        if let contentData = UserDefaults.standard.data(forKey: "ContentVectors"),
           let loadedContentVectors = try? decoder.decode([ContentVector].self, from: contentData) {
            contentVectors = loadedContentVectors
        }
        
        logger.info("Loaded vector database: \(self.urlVectors.count) URLs, \(self.contentVectors.count) content items")
    }
    
    // MARK: - Statistics
    
    var vectorCount: Int {
        urlVectors.count + contentVectors.count
    }
    
    var urlCount: Int {
        urlVectors.count
    }
    
    var contentCount: Int {
        contentVectors.count
    }
}

// MARK: - Data Models

// Note: Using ContentType from AppleIntelligenceService.swift to avoid duplication

struct URLVector: Codable, Identifiable {
    let id: UUID
    let url: String
    let title: String
    let description: String
    let content: String
    let embedding: [Float]
    let timestamp: Date
}

struct ContentVector: Codable, Identifiable {
    let id: UUID
    let content: String
    let type: ContentType
    let embedding: [Float]
    let timestamp: Date
}

struct URLSearchResult {
    let url: String
    let title: String
    let description: String
    let similarity: Float
    let timestamp: Date
}

struct ContentSearchResult {
    let content: String
    let type: ContentType
    let similarity: Float
    let timestamp: Date
}

struct SemanticSearchResult {
    let title: String
    let content: String
    let type: ContentType
    let similarity: Float
    let timestamp: Date
    let url: String?
}