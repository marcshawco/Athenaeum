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
        // Hand the caller's live document set to the retriever so orphan
        // chunks from deleted/renamed docs can't poison the prompt.
        let liveIDs: Set<UUID>? = fallbackDocuments.isEmpty
            ? nil
            : Set(fallbackDocuments.map(\.id))
        let results = await retrieveRelevantChunks(
            queryEmbedding: queryEmbedding,
            maxContext: maxContext,
            knownDocumentIDs: liveIDs
        )

        let fallbackChunks = results.isEmpty
            ? fallbackContextChunks(for: retrievalQuery, documents: fallbackDocuments, maxContext: maxContext)
            : []
        let documentLookup = Dictionary(uniqueKeysWithValues: fallbackDocuments.map { ($0.id, $0.title) })

        // Context budget: llama.cpp is configured with a 4 K context window
        // and we reserve ~1 K for the generated answer + system + history.
        // 8000 chars ≈ 2 K tokens, which keeps the prompt comfortably inside
        // the budget so the sampler doesn't drift into invalid tokens
        // (the "Token decode failed" trail).
        let perChunkCharBudget = 1200
        let totalContextCharBudget = 8000

        func packChunks<T>(_ items: [T], titleFor: (T) -> String, textFor: (T) -> String) -> String {
            var blocks: [String] = []
            var used = 0
            for (i, item) in items.enumerated() {
                let trimmed = String(textFor(item).prefix(perChunkCharBudget))
                let block = "[Source \(i + 1)] \(titleFor(item))\n\(trimmed)"
                if used + block.count > totalContextCharBudget && !blocks.isEmpty { break }
                blocks.append(block)
                used += block.count
            }
            return blocks.joined(separator: "\n\n")
        }

        let contextText: String
        if !results.isEmpty {
            contextText = packChunks(
                results,
                titleFor: { documentLookup[$0.entry.documentID]
                            ?? "Document \($0.entry.documentID.uuidString.prefix(8))" },
                textFor: { $0.entry.text }
            )
        } else if !fallbackChunks.isEmpty {
            contextText = packChunks(
                fallbackChunks,
                titleFor: { $0.document.title },
                textFor: { $0.text }
            )
        } else {
            contextText = "No documents are available yet. Ask the user to import and process documents first."
        }

        // Build the full message list: system + conversation history + current question
        var messages: [ChatMessage] = [
            ChatMessage(role: .system, content: """
                You are a helpful document assistant for Athenaeum, a macOS document library app.
                This is an ongoing chat, so use the conversation history to understand follow-up questions.
                Answer the user's latest question using ONLY the retrieved document context below.

                FORMATTING — IMPORTANT:
                - Use clear Markdown structure. Use blank lines between paragraphs and list items.
                - For step-by-step instructions, use numbered lists ("1.", "2.", …) with each step on its own line.
                - For supporting points or examples, use bulleted lists with "- " on their own line.
                - Use **bold** for key terms, document titles, and short labels at the start of a list item ("**Description:** …").
                - Use short headings like "## Heading" only when grouping a long answer; do not over-section short answers.
                - Never inline a list as comma-separated text — give each item its own line.

                CITATION FORMAT — IMPORTANT:
                - Cite sources inline as bracketed numbers like [1] or [2], right after the sentence or clause they support.
                - Do NOT write the word "Source" — just [1], [2], [3].
                - Do NOT add a "References:" section, footnote list, or trailing list of sources at the end of your answer. Cite only inline.
                - If two consecutive sentences share the same source, you may cite it once at the end of the second sentence.
                - It is fine to cite multiple sources together: [1][3].

                If the retrieved context is insufficient, say what is missing instead of guessing.
                Be concise, but preserve important dates, names, amounts, and document titles.

                Retrieved context:
                \(contextText)
                """)
        ]
        // Include up to last 6 history turns (user + assistant only) for
        // multi-turn context. 10 was too aggressive — combined with retrieved
        // chunks it could overflow the 4K context window and trigger the
        // sampler's "Token decode failed" path.
        let recentHistory = history.suffix(6).filter { $0.role == .user || $0.role == .assistant }
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

    private func retrieveRelevantChunks(
        queryEmbedding: [Float],
        maxContext: Int,
        knownDocumentIDs: Set<UUID>? = nil
    ) async -> [SearchResult] {
        // Over-fetch so that filtering for live docs still leaves us with
        // enough chunks to satisfy `maxContext`. 4× is plenty even when most
        // of the index is orphaned.
        let overfetch = max(maxContext * 4, 20)

        func filterToLive(_ results: [SearchResult]) -> [SearchResult] {
            guard let live = knownDocumentIDs else { return results }
            return results.filter { live.contains($0.entry.documentID) }
        }

        let strictResults = await vectorStore.search(query: queryEmbedding, topK: overfetch, threshold: 0.3)
        let strictLive = Array(filterToLive(strictResults).prefix(maxContext))
        if !strictLive.isEmpty { return strictLive }

        let looseResults = await vectorStore.search(query: queryEmbedding, topK: overfetch, threshold: -1)
        let looseLive = Array(filterToLive(looseResults).prefix(maxContext))
        return looseLive
    }

    // MARK: - Index sanitization

    /// Drops every embedding whose document is not in `liveIDs`. Returns the
    /// number of orphan entries removed. Cheap to run on launch / from a
    /// "Rebuild Index" button — keeps the store in lock-step with SwiftData.
    @discardableResult
    func pruneOrphans(liveDocumentIDs: Set<UUID>) async -> Int {
        let indexed = await vectorStore.indexedDocumentIDs
        let orphans = indexed.subtracting(liveDocumentIDs)
        for id in orphans {
            await vectorStore.removeEntries(forDocument: id)
        }
        if !orphans.isEmpty {
            try? await vectorStore.save()
        }
        return orphans.count
    }

    /// Nuke the entire index and re-embed every passed-in document. Used by
    /// the "Rebuild Vector Index" action in Settings ▸ Storage.
    func rebuildIndex(from documents: [(id: UUID, text: String)]) async throws {
        // Clear by removing each known document; cheap and avoids touching
        // VectorStore internals.
        let existing = await vectorStore.indexedDocumentIDs
        for id in existing {
            await vectorStore.removeEntries(forDocument: id)
        }
        try? await vectorStore.save()
        for doc in documents where !doc.text.isEmpty {
            try await indexDocument(id: doc.id, text: doc.text)
        }
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
