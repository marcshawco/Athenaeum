import Foundation

// MARK: - Llama.cpp Swift Bridge
//
// Compiles in two modes:
//   WITH llama.cpp linked  → real inference via Metal-accelerated GGUF models
//   WITHOUT llama.cpp      → graceful LlamaError.notLinked so the rest of the
//                            app builds and runs; models show "Not Linked" status

#if canImport(llama)
import llama
#endif

// MARK: - Inference Configuration

struct LlamaInferenceConfig: Sendable {
    var maxTokens: Int    = 512
    var temperature: Float = 0.7
    var topP: Float        = 0.9
    var topK: Int          = 40
    var repeatPenalty: Float = 1.1
    var seed: UInt32       = 0xFFFF_FFFF   // UINT32_MAX — avoids Swift 6 @MainActor on UInt32.max
    var batchSize: Int     = 512
    var contextSize: Int   = 4096
    var gpuLayers: Int32   = -1   // -1 = all layers to GPU (Metal)
    /// 0 = auto: llama.cpp will use hardware concurrency. Avoids @MainActor ProcessInfo in init.
    var nThreads: Int32    = 0

    // Static computed properties are nonisolated in Swift 6 — no global actor isolation issue.
    static var tagging: LlamaInferenceConfig {
        // Tagging needs a much larger context than chat: the prompt carries
        // the full 500-type taxonomy, the 1,100+-term tag pool, three few-shot
        // examples, and 8 KB of document body — easily 10K tokens before the
        // output budget. Bumped from 8K to 16K when the pool grew past 1,000
        // slugs. Qwen 2.5 14B supports 32K natively, so 16K is well within
        // bounds. KV-cache RAM at 16K is roughly 2-4 GB on a 14B Q4 — fine
        // on any modern Apple Silicon machine that can already load the
        // weights themselves.
        var config = tuned(LlamaInferenceConfig(maxTokens: 768, temperature: 0.1, topP: 0.95, topK: 20, repeatPenalty: 1.0))
        config.contextSize = max(config.contextSize, 16384)
        return config
    }

    static var chat: LlamaInferenceConfig {
        tuned(LlamaInferenceConfig(maxTokens: 1024, temperature: 0.7, topP: 0.9, topK: 40, repeatPenalty: 1.1))
    }

    static var ocr: LlamaInferenceConfig {
        tuned(LlamaInferenceConfig(maxTokens: 2048, temperature: 0.1, topP: 0.95, topK: 20, repeatPenalty: 1.0))
    }

    static var embedding: LlamaInferenceConfig {
        var config = LlamaInferenceConfig(
            maxTokens: 0,
            temperature: 0,
            topP: 1,
            topK: 1,
            repeatPenalty: 1.0,
            batchSize: 512,
            contextSize: 512,
            gpuLayers: configuredGPULayers
        )
        config.nThreads = configuredThreadCount
        return config
    }

    private static func tuned(_ config: LlamaInferenceConfig) -> LlamaInferenceConfig {
        var config = config
        config.contextSize = configuredContextSize
        config.gpuLayers = configuredGPULayers
        config.nThreads = configuredThreadCount
        return config
    }

    private static var configuredContextSize: Int {
        let value = UserDefaults.standard.integer(forKey: "contextSize")
        return [2048, 4096, 8192].contains(value) ? value : 4096
    }

    private static var configuredGPULayers: Int32 {
        guard UserDefaults.standard.object(forKey: "maxGPULayers") != nil else { return -1 }
        return Int32(UserDefaults.standard.integer(forKey: "maxGPULayers"))
    }

    private static var configuredThreadCount: Int32 {
        let value = UserDefaults.standard.integer(forKey: "llamaThreadCount")
        return value > 0 ? Int32(value) : 0
    }
}

// MARK: - Llama Context

actor LlamaContext {
    let descriptor: LLMModelDescriptor
    let modelPath: URL
    private var config: LlamaInferenceConfig
    private var isLoaded = false

#if canImport(llama)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
#endif

    init(descriptor: LLMModelDescriptor, modelPath: URL, config: LlamaInferenceConfig) {
        self.descriptor = descriptor
        self.modelPath  = modelPath
        self.config     = config
    }

    // MARK: - Lifecycle

    func load() throws {
        guard !isLoaded else { return }
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw LlamaError.modelNotFound(modelPath.path)
        }

#if canImport(llama)
        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.gpuLayers
        model = llama_model_load_from_file(modelPath.path, modelParams)
        guard model != nil else { throw LlamaError.failedToLoad }

        // Resolve thread count: 0 = auto (use available cores minus 2 for UI)
        let resolvedThreads: Int32 = config.nThreads > 0
            ? config.nThreads
            : Int32(max(1, ProcessInfo.processInfo.processorCount - 2))

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx           = UInt32(config.contextSize)
        ctxParams.n_batch         = UInt32(config.batchSize)
        ctxParams.n_threads       = resolvedThreads
        ctxParams.n_threads_batch = resolvedThreads
        ctx = llama_init_from_model(model, ctxParams)
        guard ctx != nil else { throw LlamaError.failedToCreateContext }

        let sparams = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(config.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(Int32(config.topK)))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(config.topP, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(config.seed))
        isLoaded = true
#else
        throw LlamaError.notLinked
#endif
    }

    func unload() {
        guard isLoaded else { return }
#if canImport(llama)
        if let s = sampler { llama_sampler_free(s) }
        if let c = ctx     { llama_free(c) }
        if let m = model   { llama_model_free(m) }
        sampler = nil; ctx = nil; model = nil
#endif
        isLoaded = false
    }

    // MARK: - Generation

    func generate(prompt: String, config override: LlamaInferenceConfig? = nil) throws -> String {
        guard isLoaded else { throw LlamaError.modelNotLoaded }
#if canImport(llama)
        guard let ctx, let model, let sampler else { throw LlamaError.modelNotLoaded }
        let cfg = override ?? config
        guard let vocab = llama_model_get_vocab(model) else { throw LlamaError.failedToLoad }
        llama_memory_clear(llama_get_memory(ctx), true)

        let tokens = tokenize(prompt, vocab: vocab)
        guard !tokens.isEmpty else { return "" }
        try evalTokens(tokens, ctx: ctx, batchSize: cfg.batchSize)

        var output = ""
        var nPast = Int32(tokens.count)
        var batch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch) }

        for _ in 0..<cfg.maxTokens {
            let tok = llama_sampler_sample(sampler, ctx, -1)
            llama_sampler_accept(sampler, tok)
            if llama_vocab_is_eog(vocab, tok) { break }
            output += tokenToPiece(tok, vocab: vocab)
            batchClear(&batch)
            batchAdd(&batch, token: tok, pos: nPast, seqIDs: [0], logits: true)
            nPast += 1
            guard llama_decode(ctx, batch) == 0 else { break }
        }
        return output
#else
        throw LlamaError.notLinked
#endif
    }

    func generateStream(
        messages: [ChatMessage],
        config override: LlamaInferenceConfig? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
#if canImport(llama)
            guard isLoaded, let ctx = self.ctx, let model = self.model, let sampler = self.sampler else {
                continuation.finish(throwing: LlamaError.modelNotLoaded)
                return
            }
            let cfg = override ?? self.config
            let prompt = self.chatTemplate(messages)
            guard let vocab = llama_model_get_vocab(model) else {
                continuation.finish(throwing: LlamaError.failedToLoad)
                return
            }

            let task = Task {
                do {
                    llama_memory_clear(llama_get_memory(ctx), true)
                    let tokens = self.tokenize(prompt, vocab: vocab)
                    guard !tokens.isEmpty else { continuation.finish(); return }
                    try self.evalTokens(tokens, ctx: ctx, batchSize: cfg.batchSize)

                    var nPast = Int32(tokens.count)
                    var batch = llama_batch_init(1, 0, 1)
                    defer { llama_batch_free(batch) }

                    for _ in 0..<cfg.maxTokens {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        let tok = llama_sampler_sample(sampler, ctx, -1)
                        llama_sampler_accept(sampler, tok)
                        if llama_vocab_is_eog(vocab, tok) { break }
                        continuation.yield(self.tokenToPiece(tok, vocab: vocab))
                        self.batchClear(&batch)
                        self.batchAdd(&batch, token: tok, pos: nPast, seqIDs: [0], logits: true)
                        nPast += 1
                        guard llama_decode(ctx, batch) == 0 else { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
#else
            continuation.finish(throwing: LlamaError.notLinked)
#endif
        }
    }

    func embed(_ text: String) throws -> [Float] {
        guard isLoaded else { throw LlamaError.modelNotLoaded }
#if canImport(llama)
        guard let ctx, let model else { throw LlamaError.modelNotLoaded }
        guard let vocab = llama_model_get_vocab(model) else { throw LlamaError.failedToLoad }
        llama_set_embeddings(ctx, true)
        defer { llama_set_embeddings(ctx, false) }
        llama_memory_clear(llama_get_memory(ctx), true)

        var tokens = tokenize(text, vocab: vocab)
        guard !tokens.isEmpty else { return [] }

        // CRITICAL: truncate to fit within both n_batch and n_ctx.
        // A 512-word chunk can tokenise to 700–900+ tokens; exceeding n_batch causes
        // GGML_ASSERT(batch.n_tokens <= cparams.n_batch) → ggml_abort() → SIGABRT.
        // The limit is the smaller of the two: batchSize (default 512) and contextSize.
        let hardLimit = min(config.batchSize, config.contextSize) - 2  // leave 2 slots headroom
        if tokens.count > hardLimit {
            tokens = Array(tokens.prefix(hardLimit))
        }

        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        for (i, tok) in tokens.enumerated() {
            // Only request logits for the final token (needed by llama_get_embeddings_seq)
            batchAdd(&batch, token: tok, pos: Int32(i), seqIDs: [0], logits: i == tokens.count - 1)
        }
        guard llama_decode(ctx, batch) == 0 else { throw LlamaError.decodeFailed }

        let nEmbd = Int(llama_model_n_embd(model))
        guard nEmbd > 0, let ptr = llama_get_embeddings_seq(ctx, 0) else {
            throw LlamaError.embeddingFailed
        }

        var embd = Array(UnsafeBufferPointer(start: ptr, count: nEmbd))
        let norm = sqrt(embd.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { embd = embd.map { $0 / norm } }
        return embd
#else
        throw LlamaError.notLinked
#endif
    }

    // MARK: - Helpers

#if canImport(llama)
    private func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let n = Int32(text.utf8.count) + 16
        var tokens = [llama_token](repeating: 0, count: Int(n))
        let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, n, true, true)
        guard count >= 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }

    private func tokenToPiece(_ token: llama_token, vocab: OpaquePointer) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buf, 256, 0, false)
        guard n > 0 else { return "" }
        buf[Int(n)] = 0
        return String(cString: buf)
    }

    /// Manually clear a batch (not provided in the C API)
    private func batchClear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }

    /// Manually add a token to a batch (not provided in the C API)
    private func batchAdd(_ batch: inout llama_batch, token: llama_token, pos: llama_pos, seqIDs: [llama_seq_id], logits: Bool) {
        let idx = Int(batch.n_tokens)
        batch.token[idx]    = token
        batch.pos[idx]      = pos
        batch.n_seq_id[idx] = Int32(seqIDs.count)
        for (s, sid) in seqIDs.enumerated() {
            batch.seq_id[idx]![s] = sid
        }
        batch.logits[idx] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    private func evalTokens(_ tokens: [llama_token], ctx: OpaquePointer, batchSize: Int) throws {
        var batch = llama_batch_init(Int32(batchSize), 0, 1)
        defer { llama_batch_free(batch) }
        var i = 0
        while i < tokens.count {
            batchClear(&batch)
            let end = min(i + batchSize, tokens.count)
            for j in i..<end {
                batchAdd(&batch, token: tokens[j], pos: Int32(j), seqIDs: [0], logits: j == tokens.count - 1)
            }
            guard llama_decode(ctx, batch) == 0 else { throw LlamaError.decodeFailed }
            i += batchSize
        }
    }

    private func chatTemplate(_ messages: [ChatMessage]) -> String {
        messages.map { msg in
            switch msg.role {
            case .system:    return "<|im_start|>system\n\(msg.content)<|im_end|>"
            case .user:      return "<|im_start|>user\n\(msg.content)<|im_end|>"
            case .assistant: return "<|im_start|>assistant\n\(msg.content)<|im_end|>"
            }
        }.joined(separator: "\n") + "\n<|im_start|>assistant\n"
    }
#endif
}

// MARK: - Vision Context

actor LlamaVisionContext {
    private let textCtx: LlamaContext
    private let ocrService = VisionOCRService()
    private var isLoaded = false

    init(descriptor: LLMModelDescriptor, modelPath: URL) {
        // Construct OCR config inline — avoids Swift 6 default-param actor-isolation warning
        let ocrConfig = LlamaInferenceConfig(maxTokens: 2048, temperature: 0.1, topP: 0.95,
                                              topK: 20, repeatPenalty: 1.0)
        textCtx = LlamaContext(descriptor: descriptor, modelPath: modelPath, config: ocrConfig)
    }

    func load() async throws {
        try await textCtx.load()
        isLoaded = true
    }

    func unload() async {
        await textCtx.unload()
        isLoaded = false
    }

    /// Extract text from an image using Apple Vision OCR, then optionally
    /// clean / structure the result through the LLM.
    func extractText(from imageData: Data, prompt: String? = nil) async throws -> String {
        // Step 1: Native OCR via Apple Vision framework (always works, no model needed)
        let rawOCR = try await ocrService.recognizeText(in: imageData)
        guard !rawOCR.isEmpty else { return "" }

        // Step 2: If the LLM is loaded, use it to clean up and structure the raw OCR text
        guard isLoaded else { return rawOCR }

        let cleanupInstruction = prompt ?? """
            The following text was extracted from a document image via OCR. \
            Clean it up: fix obvious OCR errors, restore logical reading order, \
            merge broken lines, and preserve the document structure (headers, paragraphs, tables). \
            Return only the cleaned text, no commentary.
            """
        let cleanupPrompt = """
            \(cleanupInstruction)

            Raw OCR text:
            \(rawOCR)
            """
        let ocrConfig = LlamaInferenceConfig(maxTokens: 2048, temperature: 0.1, topP: 0.95, topK: 20, repeatPenalty: 1.0)

        do {
            let cleaned = try await textCtx.generate(prompt: cleanupPrompt, config: ocrConfig)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return isPlausibleCleanedOCR(trimmed, rawOCR: rawOCR) ? trimmed : rawOCR
        } catch {
            // LLM cleanup failed — return raw OCR, which is still useful
            return rawOCR
        }
    }

    private func isPlausibleCleanedOCR(_ cleaned: String, rawOCR: String) -> Bool {
        guard !cleaned.isEmpty else { return false }
        if cleaned.count > max(rawOCR.count * 4, rawOCR.count + 2_000) { return false }

        let rawTerms = rawOCR
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard !rawTerms.isEmpty else { return true }

        let cleanedLower = cleaned.lowercased()
        let requiredHits = min(3, rawTerms.count)
        let hits = Set(rawTerms).filter { cleanedLower.contains($0) }.count
        return hits >= requiredHits
    }
}

// MARK: - Errors

enum LlamaError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case failedToLoad
    case failedToCreateContext
    case decodeFailed
    case tokenizationFailed
    case embeddingFailed
    case notLinked

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let p):  "Model file not found: \(p)"
        case .modelNotLoaded:        "Model not loaded — call load() first"
        case .failedToLoad:          "Failed to load GGUF model"
        case .failedToCreateContext: "Failed to create llama.cpp context"
        case .decodeFailed:          "Token decode failed — the prompt likely exceeded the model's context window. Try Settings ▸ Storage ▸ Rebuild Vector Index, or ask a shorter question."
        case .tokenizationFailed:    "Tokenization failed"
        case .embeddingFailed:       "Embedding generation failed"
        case .notLinked:             "llama.cpp not linked — add the SPM package in Xcode"
        }
    }
}
