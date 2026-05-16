import Foundation

// MARK: - RAG Service
// Retrieval-Augmented Generation pipeline:
// 1. Chunk documents into overlapping segments
// 2. Embed each chunk using the chat model's embedding mode
// 3. Store embeddings in VectorStore
// 4. At query time: embed query → retrieve top-k chunks → augment prompt → generate

@Observable
final class RAGService {
    private let llmService: LLMServiceProtocol
    private let vectorStore: VectorStore
    private(set) var isIndexing = false
    private(set) var indexingProgress: Double = 0

    /// Role used to generate embeddings. The chat model (Mistral) works well for this.
    private let embeddingRole: LLMRole = .chat

    init(llmService: LLMServiceProtocol, vectorStore: VectorStore) {
        self.llmService = llmService
        self.vectorStore = vectorStore
    }

    // MARK: - Document Indexing

    func indexDocument(id: UUID, text: String) async throws {
        isIndexing = true
        indexingProgress = 0
        defer { isIndexing = false }

        // Remove stale entries for this doc first
        await vectorStore.removeEntries(forDocument: id)

        let settings = chunkSettings
        let chunks = chunkText(text, chunkSize: settings.size, overlap: settings.overlap)
        guard !chunks.isEmpty else { return }

        var entries: [EmbeddingEntry] = []

        for (index, chunk) in chunks.enumerated() {
            indexingProgress = Double(index) / Double(chunks.count)
            let embedding = try await generateEmbedding(for: chunk.text)

            let entry = EmbeddingEntry(
                id: UUID(),
                documentID: id,
                chunkIndex: index,
                text: chunk.text,
                embedding: embedding,
                metadata: EmbeddingEntry.ChunkMetadata(
                    pageNumber: chunk.pageNumber,
                    startOffset: chunk.startOffset,
                    endOffset: chunk.endOffset
                )
            )
            entries.append(entry)
        }

        await vectorStore.addBatch(entries)
        try await vectorStore.save()
        indexingProgress = 1.0
    }

    func removeDocument(id: UUID) async throws {
        await vectorStore.removeEntries(forDocument: id)
        try await vectorStore.save()
    }

    // MARK: - Query

    func query(_ question: String, maxContext: Int = 5) async throws -> RAGResponse {
        let queryEmbedding = try await generateEmbedding(for: question)
        let results = await retrieveRelevantChunks(queryEmbedding: queryEmbedding, maxContext: maxContext)

        guard !results.isEmpty else {
            return RAGResponse(
                answer: "I couldn't find relevant information in your documents. Try importing more documents first.",
                sources: [],
                query: question
            )
        }

        let contextText = results.enumerated().map { i, result in
            "[Source \(i + 1)] (relevance: \(result.relevancePercent)%)\n\(result.entry.text)"
        }.joined(separator: "\n\n")

        let prompt = """
        You are a helpful document assistant. Answer the question using ONLY the context below.
        Cite sources as [Source N]. If the context is insufficient, say so.

        Context:
        \(contextText)

        Question: \(question)
        Answer:
        """

        let answer = try await llmService.generate(
            role: .chat,
            prompt: prompt,
            maxTokens: 1024,
            temperature: 0.7
        )

        let sources = results.map { r in
            RAGSource(
                documentID: r.entry.documentID,
                chunkText: String(r.entry.text.prefix(200)),
                relevance: r.score,
                pageNumber: r.entry.metadata.pageNumber
            )
        }

        return RAGResponse(answer: answer, sources: sources, query: question)
    }

    func queryStream(
        _ question: String,
        history: [ChatMessage] = [],
        maxContext: Int = 5,
        fallbackDocuments: [RAGDocumentContext] = []
    ) async throws -> (stream: AsyncThrowingStream<String, Error>, sources: [RAGSource]) {
        let retrievalQuery = retrievalQuery(for: question, history: history)
        let queryEmbedding = try await generateEmbedding(for: retrievalQuery)
        let results = await retrieveRelevantChunks(queryEmbedding: queryEmbedding, maxContext: maxContext)

        let fallbackChunks = results.isEmpty
            ? fallbackContextChunks(for: retrievalQuery, documents: fallbackDocuments, maxContext: maxContext)
            : []
        let documentLookup = Dictionary(uniqueKeysWithValues: fallbackDocuments.map { ($0.id, $0.title) })

        let contextText: String
        if !results.isEmpty {
            contextText = results.enumerated().map { i, r in
                let title = documentLookup[r.entry.documentID] ?? "Document \(r.entry.documentID.uuidString.prefix(8))"
                return "[Source \(i + 1)] \(title)\n\(r.entry.text)"
            }.joined(separator: "\n\n")
        } else if !fallbackChunks.isEmpty {
            contextText = fallbackChunks.enumerated().map { i, chunk in
                "[Source \(i + 1)] \(chunk.document.title)\n\(chunk.text)"
            }.joined(separator: "\n\n")
        } else {
            contextText = "No documents are available yet. Ask the user to import and process documents first."
        }

        // Build the full message list: system + conversation history + current question
        var messages: [ChatMessage] = [
            ChatMessage(role: .system, content: """
                You are a helpful document assistant for Athenaeum, a macOS document library app.
                This is an ongoing chat, so use the conversation history to understand follow-up questions.
                Answer the user's latest question using ONLY the retrieved document context below.
                Cite document evidence as [Source N] when you use it.
                If the retrieved context is insufficient, say what is missing instead of guessing.
                Be concise, but preserve important dates, names, amounts, and document titles.

                Retrieved context:
                \(contextText)
                """)
        ]
        // Include up to last 10 history turns (user + assistant only) for multi-turn context
        let recentHistory = history.suffix(10).filter { $0.role == .user || $0.role == .assistant }
        messages.append(contentsOf: recentHistory)
        messages.append(ChatMessage(role: .user, content: question))

        let stream = llmService.generateStream(
            role: .chat,
            messages: messages,
            maxTokens: 900,
            temperature: 0.45
        )

        let sources: [RAGSource] = results.isEmpty
            ? fallbackChunks.map { chunk in
                RAGSource(
                    documentID: chunk.document.id,
                    documentTitle: chunk.document.title,
                    chunkText: String(chunk.text.prefix(200)),
                    relevance: chunk.score,
                    pageNumber: nil
                )
            }
            : results.map { r in
                RAGSource(
                documentID: r.entry.documentID,
                documentTitle: documentLookup[r.entry.documentID],
                chunkText: String(r.entry.text.prefix(200)),
                relevance: r.score,
                pageNumber: r.entry.metadata.pageNumber
                )
            }

        return (stream, sources)
    }

    private func retrievalQuery(for question: String, history: [ChatMessage]) -> String {
        let recentUserTurns = history
            .filter { $0.role == .user }
            .suffix(3)
            .map(\.content)

        let recentAssistantTurns = history
            .filter { $0.role == .assistant }
            .suffix(1)
            .map { String($0.content.prefix(700)) }

        return (recentUserTurns + recentAssistantTurns + [question])
            .joined(separator: "\n")
    }

    private func retrieveRelevantChunks(queryEmbedding: [Float], maxContext: Int) async -> [SearchResult] {
        let strictResults = await vectorStore.search(query: queryEmbedding, topK: maxContext, threshold: 0.3)
        if !strictResults.isEmpty { return strictResults }
        return await vectorStore.search(query: queryEmbedding, topK: maxContext, threshold: -1)
    }

    // MARK: - Text Chunking

    struct TextChunk {
        let text: String
        let startOffset: Int
        let endOffset: Int
        let pageNumber: Int?
    }

    func chunkText(_ text: String, chunkSize: Int = 512, overlap: Int = 64) -> [TextChunk] {
        var chunks: [TextChunk] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        var currentPage = 1
        var wordIndex = 0
        var charOffset = 0

        while wordIndex < words.count {
            let endIndex = min(wordIndex + chunkSize, words.count)
            let chunkWords = Array(words[wordIndex..<endIndex])
            let chunkText = chunkWords.joined(separator: " ")

            for word in chunkWords where word.contains("\u{0C}") { currentPage += 1 }

            chunks.append(TextChunk(
                text: chunkText,
                startOffset: charOffset,
                endOffset: charOffset + chunkText.count,
                pageNumber: currentPage
            ))

            charOffset += chunkText.count
            wordIndex += max(1, chunkSize - overlap)
        }

        return chunks
    }

    // MARK: - Embedding Generation

    private func generateEmbedding(for text: String) async throws -> [Float] {
        do {
            // Use the chat model in embedding mode via llama.cpp
            return try await llmService.embed(role: embeddingRole, text: text)
        } catch LlamaError.modelNotFound {
            // Model not installed yet — fall back to pseudo-embedding for dev/testing
            return pseudoEmbedding(for: text, dimensions: 4096)
        } catch {
            // Any other inference error — also fall back so import doesn't fail
            return pseudoEmbedding(for: text, dimensions: 4096)
        }
    }

    private var chunkSettings: (size: Int, overlap: Int) {
        let defaults = UserDefaults.standard
        let configuredSize = defaults.integer(forKey: "chunkSize")
        let configuredOverlap = defaults.integer(forKey: "chunkOverlap")
        let size = min(max(configuredSize == 0 ? 512 : configuredSize, 128), 1024)
        let overlap = min(max(configuredOverlap, 0), min(256, size - 1))
        return (size, overlap)
    }

    // MARK: - Fallback Retrieval

    private struct FallbackChunk: Sendable {
        let document: RAGDocumentContext
        let text: String
        let score: Float
    }

    private func fallbackContextChunks(
        for question: String,
        documents: [RAGDocumentContext],
        maxContext: Int
    ) -> [FallbackChunk] {
        let eligible = documents.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !eligible.isEmpty else { return [] }

        let lowerQuestion = question.lowercased()
        let wantsRecent = ["recent", "latest", "last", "newest"].contains { lowerQuestion.contains($0) }
        let orderedDocuments = eligible.sorted {
            ($0.documentDate ?? $0.importedAt) > ($1.documentDate ?? $1.importedAt)
        }

        if wantsRecent, let document = orderedDocuments.first {
            return [FallbackChunk(
                document: document,
                text: String(document.text.prefix(3_500)),
                score: 0.92
            )]
        }

        let queryTerms = Set(lowerQuestion
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 })

        let ranked = orderedDocuments.map { document in
            let lowerText = "\(document.title) \(document.text.prefix(6_000))".lowercased()
            let termHits = queryTerms.reduce(0) { count, term in
                count + (lowerText.contains(term) ? 1 : 0)
            }
            let score = queryTerms.isEmpty
                ? Float(0.55)
                : Float(termHits) / Float(max(queryTerms.count, 1))
            return FallbackChunk(
                document: document,
                text: String(document.text.prefix(3_500)),
                score: max(0.35, score)
            )
        }

        return ranked
            .sorted {
                if $0.score == $1.score {
                    return ($0.document.documentDate ?? $0.document.importedAt) > ($1.document.documentDate ?? $1.document.importedAt)
                }
                return $0.score > $1.score
            }
            .prefix(maxContext)
            .map { $0 }
    }

    /// Deterministic hash-based pseudo-embedding. Used when no model is installed.
    /// Dimension matches Mistral 7B hidden size (4096) for future compatibility.
    private func pseudoEmbedding(for text: String, dimensions: Int) -> [Float] {
        var embedding = [Float](repeating: 0, count: dimensions)
        let tokens = text.lowercased().split(separator: " ")

        for token in tokens {
            var hash = token.hashValue
            let stride = max(1, dimensions / 64)
            var d = 0
            while d < dimensions {
                hash = hash &* 6364136223846793005 &+ 1442695040888963407
                let unsigned = UInt64(bitPattern: Int64(hash))
                let value = Float(Int(unsigned % 2001)) / 1000.0 - 1.0
                embedding[d] += value
                d += stride
            }
        }

        // L2 normalise
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { embedding = embedding.map { $0 / norm } }

        return embedding
    }
}

// MARK: - Response Types

struct RAGResponse: Sendable {
    let answer: String
    let sources: [RAGSource]
    let query: String
}

struct RAGDocumentContext: Sendable {
    let id: UUID
    let title: String
    let text: String
    let documentDate: Date?
    let importedAt: Date
}

struct RAGSource: Identifiable, Sendable {
    let id = UUID()
    let documentID: UUID
    let documentTitle: String?
    let chunkText: String
    let relevance: Float
    let pageNumber: Int?

    init(documentID: UUID, documentTitle: String? = nil, chunkText: String, relevance: Float, pageNumber: Int?) {
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.chunkText = chunkText
        self.relevance = relevance
        self.pageNumber = pageNumber
    }

    var relevancePercent: Int {
        max(0, min(100, Int((relevance * 100).rounded())))
    }
}
