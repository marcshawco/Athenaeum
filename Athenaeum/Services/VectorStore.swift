import Foundation
import Accelerate

// MARK: - Vector Store
// Local vector database for RAG. Stores document chunk embeddings and performs
// cosine similarity search using Accelerate framework for SIMD performance.

struct EmbeddingEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let documentID: UUID
    let chunkIndex: Int
    let text: String
    let embedding: [Float]
    let metadata: ChunkMetadata

    struct ChunkMetadata: Codable, Sendable {
        let pageNumber: Int?
        let startOffset: Int
        let endOffset: Int
    }
}

// MARK: - Vector Store

actor VectorStore {
    private var entries: [EmbeddingEntry] = []
    private let storageURL: URL

    /// Inferred from the first embedding stored. `nil` until first entry is added.
    private var inferredDimensions: Int?

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageURL = appSupport
                .appendingPathComponent("Athenaeum", isDirectory: true)
                .appendingPathComponent("vector_store.json")
        }
        try? FileManager.default.createDirectory(
            at: self.storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    // MARK: - CRUD

    func add(_ entry: EmbeddingEntry) {
        if inferredDimensions == nil { inferredDimensions = entry.embedding.count }
        entries.append(entry)
    }

    func addBatch(_ newEntries: [EmbeddingEntry]) {
        if inferredDimensions == nil { inferredDimensions = newEntries.first?.embedding.count }
        entries.append(contentsOf: newEntries)
    }

    func removeEntries(forDocument documentID: UUID) {
        entries.removeAll { $0.documentID == documentID }
    }

    func entryCount(forDocument documentID: UUID) -> Int {
        entries.filter { $0.documentID == documentID }.count
    }

    var totalEntries: Int { entries.count }

    /// Number of distinct documents that currently have at least one
    /// embedding chunk in the store. Used to surface "re-index needed"
    /// hints when the vault has documents that aren't represented here.
    var indexedDocumentCount: Int {
        Set(entries.map(\.documentID)).count
    }

    /// Set of document IDs currently represented in the index.
    var indexedDocumentIDs: Set<UUID> {
        Set(entries.map(\.documentID))
    }

    // MARK: - Search

    /// Find the top-k most similar chunks to a query embedding.
    func search(query: [Float], topK: Int = 5, threshold: Float = 0.3) -> [SearchResult] {
        guard !entries.isEmpty, !query.isEmpty else { return [] }

        var results: [(entry: EmbeddingEntry, score: Float)] = []

        for entry in entries {
            let score = cosineSimilarity(query, entry.embedding)
            if score >= threshold {
                results.append((entry, score))
            }
        }

        results.sort { $0.score > $1.score }
        return results.prefix(topK).map { SearchResult(entry: $0.entry, score: $0.score) }
    }

    /// Search within a specific document's chunks.
    func searchInDocument(query: [Float], documentID: UUID, topK: Int = 5) -> [SearchResult] {
        guard !entries.isEmpty, !query.isEmpty else { return [] }

        let docEntries = entries.filter { $0.documentID == documentID }
        var results: [(entry: EmbeddingEntry, score: Float)] = []

        for entry in docEntries {
            let score = cosineSimilarity(query, entry.embedding)
            results.append((entry, score))
        }

        results.sort { $0.score > $1.score }
        return results.prefix(topK).map { SearchResult(entry: $0.entry, score: $0.score) }
    }

    // MARK: - Persistence

    func save() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storageURL, options: .atomic)
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            entries = try JSONDecoder().decode([EmbeddingEntry].self, from: data)
            inferredDimensions = entries.first?.embedding.count
        } catch {
            entries = []
            inferredDimensions = nil

            let corruptURL = storageURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: storageURL, to: corruptURL)
            throw error
        }
    }

    // MARK: - Cosine Similarity (Accelerate)

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let count = vDSP_Length(a.count)

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        a.withUnsafeBufferPointer { aPtr in
            b.withUnsafeBufferPointer { bPtr in
                vDSP_dotpr(aPtr.baseAddress!, 1, bPtr.baseAddress!, 1, &dotProduct, count)
                vDSP_svesq(aPtr.baseAddress!, 1, &normA, count)
                vDSP_svesq(bPtr.baseAddress!, 1, &normB, count)
            }
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let entry: EmbeddingEntry
    let score: Float

    var relevancePercent: Int {
        Int(score * 100)
    }
}
