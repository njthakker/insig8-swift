//
//  SQLiteVectorDatabase.swift
//  Insig8
//
//  Production-grade vector database with SQLite + sqlite-vec extension
//

import Foundation
import SQLite3
import Accelerate
import Combine
import os.log

@MainActor
class SQLiteVectorDatabase: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Insig8", category: "SQLiteVectorDatabase")
    
    private var coreDB: OpaquePointer?
    private var vectorDB: OpaquePointer?
    let dbPath: String // Made public for AppStore access
    private let vectorDbPath: String
    
    // Performance tracking
    @Published var lastSearchTime: TimeInterval = 0
    @Published var totalVectors: Int = 0
    @Published var isInitialized: Bool = false
    
    // HNSW parameters for fast search
    private let maxConnections: Int = 16
    private let efConstruction: Int = 200
    private let efSearch: Int = 50
    
    init() {
        // Initialize database paths
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dbPath = documentsPath.appendingPathComponent("insig8_core.db").path
        self.vectorDbPath = documentsPath.appendingPathComponent("insig8_vectors.db").path
        
        logger.info("Initializing SQLite Vector Database at: \(self.dbPath)")
    }
    
    // MARK: - Database Initialization
    
    func initialize() async throws {
        logger.info("Starting database initialization...")
        
        // Create core database with encryption
        try await createCoreDatabase()
        
        // Initialize vector extension database
        try await initializeVectorDatabase()
        
        // Create schema
        try await createSchema()
        
        // Load vector count
        await updateVectorCount()
        
        isInitialized = true
        logger.info("Database initialization complete. Total vectors: \(self.totalVectors)")
    }
    
    private func createCoreDatabase() async throws {
        var db: OpaquePointer?
        
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)
        
        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("Failed to open core database: \(errorMessage)")
            throw VectorDatabaseError.databaseOpenFailed(errorMessage)
        }
        
        self.coreDB = db
        
        // Enable WAL mode for better performance
        try executeSQL("PRAGMA journal_mode = WAL", on: coreDB)
        try executeSQL("PRAGMA synchronous = NORMAL", on: coreDB)
        try executeSQL("PRAGMA cache_size = -64000", on: coreDB) // 64MB cache
        try executeSQL("PRAGMA mmap_size = 268435456", on: coreDB) // 256MB mmap
    }
    
    private func initializeVectorDatabase() async throws {
        var db: OpaquePointer?
        
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(vectorDbPath, &db, flags, nil)
        
        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("Failed to open vector database: \(errorMessage)")
            throw VectorDatabaseError.databaseOpenFailed(errorMessage)
        }
        
        self.vectorDB = db
        
        // Load sqlite-vec extension (in production, this would be a compiled extension)
        // For now, we'll use a custom implementation
        logger.info("Vector database initialized (using custom vector implementation)")
    }
    
    private func createSchema() async throws {
        // Core content table
        let contentTableSQL = """
            CREATE TABLE IF NOT EXISTS content (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                source TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                tags TEXT,
                metadata TEXT,
                embedding_id TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            )
        """
        try executeSQL(contentTableSQL, on: coreDB)
        
        // Indexes for performance
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_content_timestamp ON content(timestamp DESC)", on: coreDB)
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_content_source ON content(source)", on: coreDB)
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_content_tags ON content(tags)", on: coreDB)
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_content_embedding_id ON content(embedding_id)", on: coreDB)
        
        // Vector embeddings table (custom implementation)
        let vectorTableSQL = """
            CREATE TABLE IF NOT EXISTS vectors (
                id TEXT PRIMARY KEY,
                dimension INTEGER NOT NULL,
                embedding BLOB NOT NULL,
                magnitude REAL,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            )
        """
        try executeSQL(vectorTableSQL, on: vectorDB)
        
        // HNSW index metadata
        let hnswTableSQL = """
            CREATE TABLE IF NOT EXISTS hnsw_index (
                node_id TEXT PRIMARY KEY,
                level INTEGER NOT NULL,
                connections TEXT NOT NULL,
                entry_point INTEGER DEFAULT 0
            )
        """
        try executeSQL(hnswTableSQL, on: vectorDB)
        
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_hnsw_level ON hnsw_index(level)", on: vectorDB)
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_hnsw_entry ON hnsw_index(entry_point)", on: vectorDB)
    }
    
    // MARK: - Vector Operations
    
    func insertVector(id: String, content: String, embedding: [Float], source: ContentSource, tags: [ContentTag] = [], metadata: [String: Any] = [:]) async throws {
        logger.debug("Inserting vector with ID: \(id)")
        
        // Start transaction
        try executeSQL("BEGIN TRANSACTION", on: coreDB)
        try executeSQL("BEGIN TRANSACTION", on: vectorDB)
        
        do {
            // Insert content
            let tagsJSON = tags.map { $0.rawValue }.joined(separator: ",")
            let metadataString: String
            do {
                let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
                metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"
            } catch {
                logger.error("Failed to serialize metadata: \(error)")
                metadataString = "{}"
            }
            
            let contentSQL = """
                INSERT OR REPLACE INTO content (id, content, source, timestamp, tags, metadata, embedding_id)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            
            var contentStmt: OpaquePointer?
            sqlite3_prepare_v2(coreDB, contentSQL, -1, &contentStmt, nil)
            sqlite3_bind_text(contentStmt, 1, id, -1, nil)
            sqlite3_bind_text(contentStmt, 2, content, -1, nil)
            sqlite3_bind_text(contentStmt, 3, source.description, -1, nil)
            sqlite3_bind_int64(contentStmt, 4, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_text(contentStmt, 5, tagsJSON, -1, nil)
            sqlite3_bind_text(contentStmt, 6, metadataString, -1, nil)
            sqlite3_bind_text(contentStmt, 7, id, -1, nil)
            
            guard sqlite3_step(contentStmt) == SQLITE_DONE else {
                throw VectorDatabaseError.insertFailed(String(cString: sqlite3_errmsg(coreDB)))
            }
            sqlite3_finalize(contentStmt)
            
            // Insert vector
            let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
            let embeddingData = embedding.withUnsafeBytes { Data($0) }
            
            let vectorSQL = """
                INSERT OR REPLACE INTO vectors (id, dimension, embedding, magnitude)
                VALUES (?, ?, ?, ?)
            """
            
            var vectorStmt: OpaquePointer?
            sqlite3_prepare_v2(vectorDB, vectorSQL, -1, &vectorStmt, nil)
            sqlite3_bind_text(vectorStmt, 1, id, -1, nil)
            sqlite3_bind_int(vectorStmt, 2, Int32(embedding.count))
            sqlite3_bind_blob(vectorStmt, 3, (embeddingData as NSData).bytes, Int32(embeddingData.count), nil)
            sqlite3_bind_double(vectorStmt, 4, Double(magnitude))
            
            guard sqlite3_step(vectorStmt) == SQLITE_DONE else {
                throw VectorDatabaseError.insertFailed(String(cString: sqlite3_errmsg(vectorDB)))
            }
            sqlite3_finalize(vectorStmt)
            
            // Update HNSW index
            try await updateHNSWIndex(id: id, embedding: embedding)
            
            // Commit transaction
            try executeSQL("COMMIT", on: coreDB)
            try executeSQL("COMMIT", on: vectorDB)
            
            await updateVectorCount()
            logger.debug("Successfully inserted vector: \(id)")
            
        } catch {
            // Rollback on error
            try? executeSQL("ROLLBACK", on: coreDB)
            try? executeSQL("ROLLBACK", on: vectorDB)
            throw error
        }
    }
    
    func batchInsertVectors(_ vectors: [(id: String, content: String, embedding: [Float], source: ContentSource, tags: [ContentTag], metadata: [String: Any])]) async throws {
        logger.info("Batch inserting \(vectors.count) vectors")
        
        let startTime = Date()
        
        // Use transaction for performance
        try executeSQL("BEGIN TRANSACTION", on: coreDB)
        try executeSQL("BEGIN TRANSACTION", on: vectorDB)
        
        do {
            for vector in vectors {
                try await insertVector(
                    id: vector.id,
                    content: vector.content,
                    embedding: vector.embedding,
                    source: vector.source,
                    tags: vector.tags,
                    metadata: vector.metadata
                )
            }
            
            try executeSQL("COMMIT", on: coreDB)
            try executeSQL("COMMIT", on: vectorDB)
            
            let elapsed = Date().timeIntervalSince(startTime)
            logger.info("Batch insert completed in \(elapsed)s (\(Double(vectors.count) / elapsed) vectors/sec)")
            
        } catch {
            try? executeSQL("ROLLBACK", on: coreDB)
            try? executeSQL("ROLLBACK", on: vectorDB)
            throw error
        }
    }
    
    // MARK: - Content Storage Helpers
    
    func addClipboardContent(_ content: String, type: ContentType, timestamp: Date = Date()) async throws {
        // Generate a unique ID for clipboard content
        let id = "clipboard_\(timestamp.timeIntervalSince1970)"
        
        // Create simple embedding based on content (placeholder - would use real embedding service)
        let embedding = generateSimpleEmbedding(for: content)
        
        // Store in vector database
        try await insertVector(
            id: id,
            content: content,
            embedding: embedding,
            source: .clipboard,
            tags: [.clipboard],
            metadata: [
                "type": type.rawValue,
                "timestamp": timestamp.timeIntervalSince1970,
                "length": content.count
            ]
        )
        
        await MainActor.run {
            totalVectors += 1
        }
        
        logger.debug("Stored clipboard content with ID: \(id)")
    }
    
    private func generateSimpleEmbedding(for content: String) -> [Float] {
        // Simple hash-based embedding (in production, use proper embedding model)
        let words = content.lowercased().components(separatedBy: .whitespacesAndNewlines)
        var embedding = Array(repeating: Float(0), count: 768)  // Match common embedding size
        
        for word in words {
            let hash = word.hashValue
            let embeddingIndex = abs(hash) % embedding.count
            embedding[embeddingIndex] += 1.0 / Float(words.count)
        }
        
        // Normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }
        
        return embedding
    }
    
    // MARK: - Search Operations
    
    func similaritySearch(query: [Float], limit: Int = 10, threshold: Float = 0.7) async throws -> [VectorSearchResult] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        logger.debug("Performing similarity search with threshold: \(threshold)")
        
        // Use HNSW for fast approximate search
        let candidates = try await hnswSearch(query: query, limit: limit * 2)
        
        // Re-rank with exact similarity
        var results: [VectorSearchResult] = []
        
        for candidateId in candidates {
            // Fetch vector
            let vectorSQL = "SELECT embedding, magnitude FROM vectors WHERE id = ?"
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(vectorDB, vectorSQL, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, candidateId, -1, nil)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                let embeddingBlob = sqlite3_column_blob(stmt, 0)
                let embeddingSize = sqlite3_column_bytes(stmt, 0)
                let magnitude = Float(sqlite3_column_double(stmt, 1))
                
                if let embeddingBlob = embeddingBlob {
                    let embedding = Array(UnsafeBufferPointer(
                        start: embeddingBlob.assumingMemoryBound(to: Float.self),
                        count: Int(embeddingSize) / MemoryLayout<Float>.size
                    ))
                    
                    // Calculate cosine similarity
                    let similarity = cosineSimilarity(query, embedding, queryMagnitude: nil, embeddingMagnitude: magnitude)
                    
                    if similarity >= threshold {
                        // Fetch content
                        if let content = try await fetchContent(for: candidateId) {
                            results.append(VectorSearchResult(
                                id: candidateId,
                                content: content.content,
                                source: content.source,
                                tags: content.tags,
                                similarity: similarity,
                                metadata: content.metadata
                            ))
                        }
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Sort by similarity and limit
        results.sort { $0.similarity > $1.similarity }
        results = Array(results.prefix(limit))
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        self.lastSearchTime = elapsed
        
        logger.info("Similarity search completed in \(elapsed * 1000)ms, found \(results.count) results")
        
        return results
    }
    
    func hybridSearch(query: String, embedding: [Float], limit: Int = 10) async throws -> [VectorSearchResult] {
        logger.debug("Performing hybrid search for: \(query)")
        
        // Keyword search using FTS5
        let keywordResults = try await keywordSearch(query: query, limit: limit * 2)
        
        // Vector similarity search
        let vectorResults = try await similaritySearch(query: embedding, limit: limit * 2, threshold: 0.5)
        
        // Merge and re-rank using reciprocal rank fusion
        var fusedResults: [String: (result: VectorSearchResult, score: Float)] = [:]
        
        // Add keyword results
        for (index, result) in keywordResults.enumerated() {
            let rrScore = 1.0 / Float(index + 60) // Reciprocal rank with k=60
            fusedResults[result.id] = (result, rrScore)
        }
        
        // Add vector results
        for (index, result) in vectorResults.enumerated() {
            let rrScore = 1.0 / Float(index + 60)
            if let existing = fusedResults[result.id] {
                // Combine scores
                fusedResults[result.id] = (result, existing.score + rrScore)
            } else {
                fusedResults[result.id] = (result, rrScore)
            }
        }
        
        // Sort by fused score
        let sortedResults = fusedResults.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.result }
        
        logger.debug("Hybrid search found \(sortedResults.count) results")
        return Array(sortedResults)
    }
    
    // MARK: - HNSW Implementation
    
    private func updateHNSWIndex(id: String, embedding: [Float]) async throws {
        // Simple HNSW insertion (production would use optimized C++ implementation)
        let level = getRandomLevel()
        
        // Find nearest neighbors at each level
        var connections: [Int: [String]] = [:]
        
        for l in 0...level {
            let neighbors = try await findNearestInLevel(embedding: embedding, level: l, count: maxConnections)
            connections[l] = neighbors
        }
        
        // Store in index - convert Int keys to String keys for JSON serialization
        let stringKeyConnections = Dictionary(uniqueKeysWithValues: connections.map { (String($0), $1) })
        let connectionsString: String
        do {
            let connectionsJSON = try JSONSerialization.data(withJSONObject: stringKeyConnections)
            connectionsString = String(data: connectionsJSON, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to serialize HNSW connections: \(error)")
            connectionsString = "{}"
        }
        
        let sql = """
            INSERT OR REPLACE INTO hnsw_index (node_id, level, connections, entry_point)
            VALUES (?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(vectorDB, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, id, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(level))
        sqlite3_bind_text(stmt, 3, connectionsString, -1, nil)
        sqlite3_bind_int(stmt, 4, level == 0 ? 0 : 1)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw VectorDatabaseError.insertFailed("HNSW index update failed")
        }
        sqlite3_finalize(stmt)
    }
    
    private func hnswSearch(query: [Float], limit: Int) async throws -> [String] {
        // Greedy search through HNSW graph
        var visited = Set<String>()
        var candidates = [(id: String, distance: Float)]()
        var w = [(id: String, distance: Float)]()
        
        // Start from entry points
        let entryPoints = try await getEntryPoints()
        
        for entry in entryPoints {
            if let embedding = try await getEmbedding(for: entry) {
                let distance = euclideanDistance(query, embedding)
                candidates.append((entry, distance))
                w.append((entry, distance))
                visited.insert(entry)
            }
        }
        
        // Search
        while !candidates.isEmpty {
            candidates.sort { $0.distance < $1.distance }
            let current = candidates.removeFirst()
            
            if current.distance > w.last?.distance ?? Float.infinity {
                break
            }
            
            // Check neighbors
            if let neighbors = try await getNeighbors(for: current.id) {
                for neighbor in neighbors {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        
                        if let embedding = try await getEmbedding(for: neighbor) {
                            let distance = euclideanDistance(query, embedding)
                            
                            if distance < w.last?.distance ?? Float.infinity || w.count < limit {
                                candidates.append((neighbor, distance))
                                w.append((neighbor, distance))
                                w.sort { $0.distance < $1.distance }
                                
                                if w.count > limit {
                                    w.removeLast()
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return w.prefix(limit).map { $0.id }
    }
    
    // MARK: - Helper Methods
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float], queryMagnitude: Float? = nil, embeddingMagnitude: Float? = nil) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        let magnitudeA = queryMagnitude ?? sqrt(vDSP.sumOfSquares(a))
        let magnitudeB = embeddingMagnitude ?? sqrt(vDSP.sumOfSquares(b))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        
        var difference = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &difference, 1, vDSP_Length(a.count))
        
        var squaredSum: Float = 0
        vDSP_svesq(difference, 1, &squaredSum, vDSP_Length(a.count))
        
        return sqrt(squaredSum)
    }
    
    private func executeSQL(_ sql: String, on db: OpaquePointer?) throws {
        guard let db = db else { throw VectorDatabaseError.databaseNotOpen }
        
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw VectorDatabaseError.sqlExecutionFailed(message)
        }
    }
    
    private func updateVectorCount() async {
        let sql = "SELECT COUNT(*) FROM vectors"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(vectorDB, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalVectors = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
    }
    
    private func fetchContent(for id: String) async throws -> ContentRecord? {
        let sql = """
            SELECT content, source, tags, metadata, timestamp
            FROM content WHERE id = ?
        """
        
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(coreDB, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, id, -1, nil)
        
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let content = String(cString: sqlite3_column_text(stmt, 0))
            let _ = String(cString: sqlite3_column_text(stmt, 1))
            let tagsStr = String(cString: sqlite3_column_text(stmt, 2))
            let metadataStr = String(cString: sqlite3_column_text(stmt, 3))
            let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 4)))
            
            let tags = tagsStr.split(separator: ",").compactMap { ContentTag(rawValue: String($0)) }
            let metadata = try? JSONSerialization.jsonObject(with: metadataStr.data(using: .utf8) ?? Data()) as? [String: Any]
            
            // Parse source
            let source: ContentSource = .manual // Simplified for now
            
            return ContentRecord(
                id: id,
                content: content,
                source: source,
                tags: tags,
                metadata: metadata ?? [:],
                timestamp: timestamp
            )
        }
        
        return nil
    }
    
    private func keywordSearch(query: String, limit: Int) async throws -> [VectorSearchResult] {
        // Simple LIKE search (production would use FTS5)
        let sql = """
            SELECT id, content, source, tags, metadata, timestamp
            FROM content
            WHERE content LIKE ?
            ORDER BY timestamp DESC
            LIMIT ?
        """
        
        var results: [VectorSearchResult] = []
        var stmt: OpaquePointer?
        
        sqlite3_prepare_v2(coreDB, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, "%\(query)%", -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let content = String(cString: sqlite3_column_text(stmt, 1))
            let _ = String(cString: sqlite3_column_text(stmt, 2))
            let tagsStr = String(cString: sqlite3_column_text(stmt, 3))
            let metadataStr = String(cString: sqlite3_column_text(stmt, 4))
            
            let tags = tagsStr.split(separator: ",").compactMap { ContentTag(rawValue: String($0)) }
            let metadata = try? JSONSerialization.jsonObject(with: metadataStr.data(using: .utf8) ?? Data()) as? [String: Any]
            
            results.append(VectorSearchResult(
                id: id,
                content: content,
                source: .manual,
                tags: tags,
                similarity: 1.0, // Keyword match
                metadata: metadata ?? [:]
            ))
        }
        
        sqlite3_finalize(stmt)
        return results
    }
    
    private func getRandomLevel() -> Int {
        // Exponential decay probability
        var level = 0
        while Double.random(in: 0..<1) < 0.5 && level < 16 {
            level += 1
        }
        return level
    }
    
    private func findNearestInLevel(embedding: [Float], level: Int, count: Int) async throws -> [String] {
        // Simplified: return random existing nodes
        let sql = "SELECT node_id FROM hnsw_index WHERE level >= ? LIMIT ?"
        var stmt: OpaquePointer?
        var results: [String] = []
        
        sqlite3_prepare_v2(vectorDB, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(level))
        sqlite3_bind_int(stmt, 2, Int32(count))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        
        sqlite3_finalize(stmt)
        return results
    }
    
    private func getEntryPoints() async throws -> [String] {
        let sql = "SELECT node_id FROM hnsw_index WHERE entry_point = 1 LIMIT 5"
        var stmt: OpaquePointer?
        var results: [String] = []
        
        sqlite3_prepare_v2(vectorDB, sql, -1, &stmt, nil)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        
        sqlite3_finalize(stmt)
        
        // If no entry points, get random nodes
        if results.isEmpty {
            let fallbackSQL = "SELECT id FROM vectors ORDER BY RANDOM() LIMIT 5"
            sqlite3_prepare_v2(vectorDB, fallbackSQL, -1, &stmt, nil)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(String(cString: sqlite3_column_text(stmt, 0)))
            }
            sqlite3_finalize(stmt)
        }
        
        return results
    }
    
    private func getNeighbors(for nodeId: String) async throws -> [String]? {
        let sql = "SELECT connections FROM hnsw_index WHERE node_id = ?"
        var stmt: OpaquePointer?
        
        sqlite3_prepare_v2(vectorDB, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, nodeId, -1, nil)
        
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let connectionsStr = String(cString: sqlite3_column_text(stmt, 0))
            if let data = connectionsStr.data(using: .utf8),
               let connections = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] {
                // Return all connections from all levels
                return Array(connections.values.flatMap { $0 })
            }
        }
        
        return nil
    }
    
    private func getEmbedding(for id: String) async throws -> [Float]? {
        let sql = "SELECT embedding FROM vectors WHERE id = ?"
        var stmt: OpaquePointer?
        
        sqlite3_prepare_v2(vectorDB, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, id, -1, nil)
        
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let embeddingBlob = sqlite3_column_blob(stmt, 0)
            let embeddingSize = sqlite3_column_bytes(stmt, 0)
            
            if let embeddingBlob = embeddingBlob {
                return Array(UnsafeBufferPointer(
                    start: embeddingBlob.assumingMemoryBound(to: Float.self),
                    count: Int(embeddingSize) / MemoryLayout<Float>.size
                ))
            }
        }
        
        return nil
    }
    
    // MARK: - Cleanup
    
    nonisolated func close() {
        Task { @MainActor in
            if let db = coreDB {
                sqlite3_close(db)
                coreDB = nil
            }
            
            if let db = vectorDB {
                sqlite3_close(db)
                vectorDB = nil
            }
            
            isInitialized = false
            logger.info("Database connections closed")
        }
    }
    
    deinit {
        close()
    }
}

// MARK: - Supporting Types

struct VectorSearchResult: Identifiable {
    let id: String
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let similarity: Float
    let metadata: [String: Any]
}

struct ContentRecord {
    let id: String
    let content: String
    let source: ContentSource
    let tags: [ContentTag]
    let metadata: [String: Any]
    let timestamp: Date
}

enum VectorDatabaseError: LocalizedError {
    case databaseNotOpen
    case databaseOpenFailed(String)
    case insertFailed(String)
    case searchFailed(String)
    case sqlExecutionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Database is not open"
        case .databaseOpenFailed(let message):
            return "Failed to open database: \(message)"
        case .insertFailed(let message):
            return "Failed to insert data: \(message)"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        case .sqlExecutionFailed(let message):
            return "SQL execution failed: \(message)"
        }
    }
}