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

// MARK: - One-shot backend init
//
// `llama_backend_init()` is global state. Calling it on every model
// load wastes cycles and (in some llama.cpp builds) re-registers Metal
// devices unnecessarily. Gate it behind an atomic flag so it runs at
// most once per process lifetime.

// The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
// makes free functions and module-level lets default to MainActor
// isolation. This init helper is called from `LlamaContext.load()`
// — a custom-actor context — so everything here must be explicitly
// `nonisolated` to avoid an actor-hop warning.

#if canImport(llama)
nonisolated private let llamaBackendLock = NSLock()
nonisolated(unsafe) private var llamaBackendDidInit = false

nonisolated func llamaBackendInitIfNeeded() {
    llamaBackendLock.lock()
    defer { llamaBackendLock.unlock() }
    guard !llamaBackendDidInit else { return }
    llama_backend_init()
    llamaBackendDidInit = true
}
#else
nonisolated func llamaBackendInitIfNeeded() {}
#endif

// MARK: - Llama Context

actor LlamaContext {
    let descriptor: LLMModelDescriptor
    let modelPath: URL
    private var config: LlamaInferenceConfig
    private var isLoaded = false

    /// In-flight streaming generations. Incremented by `generateStream`
    /// before its producer task starts, decremented when the task ends.
    /// `unload()` awaits this reaching zero before freeing the C pointers,
    /// so a streaming task never operates on freed memory.
    private var streamGenerationsInFlight: Int = 0
    private var unloadWaiters: [CheckedContinuation<Void, Never>] = []

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
        llamaBackendInitIfNeeded()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.gpuLayers
        guard let loadedModel = llama_model_load_from_file(modelPath.path, modelParams) else {
            throw LlamaError.failedToLoad
        }

        // Rollback partial allocation on any thrown error below so we
        // don't leak GPU/RAM. Cleared at the end on success.
        var didSucceed = false
        defer {
            if !didSucceed {
                if let s = sampler { llama_sampler_free(s); sampler = nil }
                if let c = ctx     { llama_free(c); ctx = nil }
                llama_model_free(loadedModel)
                model = nil
            }
        }
        model = loadedModel

        // Resolve thread count: 0 = auto (use available cores minus 2 for UI)
        let resolvedThreads: Int32 = config.nThreads > 0
            ? config.nThreads
            : Int32(max(1, ProcessInfo.processInfo.processorCount - 2))

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx           = UInt32(config.contextSize)
        ctxParams.n_batch         = UInt32(config.batchSize)
        ctxParams.n_threads       = resolvedThreads
        ctxParams.n_threads_batch = resolvedThreads
        guard let loadedCtx = llama_init_from_model(loadedModel, ctxParams) else {
            throw LlamaError.failedToCreateContext
        }
        ctx = loadedCtx

        let sparams = llama_sampler_chain_default_params()
        guard let loadedSampler = llama_sampler_chain_init(sparams) else {
            throw LlamaError.failedToLoad
        }
        sampler = loadedSampler
        llama_sampler_chain_add(loadedSampler, llama_sampler_init_temp(config.temperature))
        llama_sampler_chain_add(loadedSampler, llama_sampler_init_top_k(Int32(config.topK)))
        llama_sampler_chain_add(loadedSampler, llama_sampler_init_top_p(config.topP, 1))
        llama_sampler_chain_add(loadedSampler, llama_sampler_init_dist(config.seed))
        isLoaded = true
        didSucceed = true
#else
        throw LlamaError.notLinked
#endif
    }

    func unload() async {
        guard isLoaded else { return }
        // Wait for any in-flight streaming generations to finish before
        // freeing the C pointers they're decoding against.
        if streamGenerationsInFlight > 0 {
            await withCheckedContinuation { cont in
                unloadWaiters.append(cont)
            }
        }
#if canImport(llama)
        if let s = sampler { llama_sampler_free(s) }
        if let c = ctx     { llama_free(c) }
        if let m = model   { llama_model_free(m) }
        sampler = nil; ctx = nil; model = nil
#endif
        isLoaded = false
    }

    /// Counter management for `generateStream`. Producer tasks call
    /// these via `Task { await self.beginStreamGeneration() }` etc.
    fileprivate func beginStreamGeneration() {
        streamGenerationsInFlight += 1
    }

    fileprivate func endStreamGeneration() {
        streamGenerationsInFlight -= 1
        if streamGenerationsInFlight == 0, !unloadWaiters.isEmpty {
            let waiters = unloadWaiters
            unloadWaiters.removeAll()
            for w in waiters { w.resume() }
        }
    }

    // MARK: - Generation

    func generate(prompt: String, config override: LlamaInferenceConfig? = nil) throws -> String {
        guard isLoaded else { throw LlamaError.modelNotLoaded }
#if canImport(llama)
        guard let ctx, let model, let sampler else { throw LlamaError.modelNotLoaded }
        let cfg = override ?? config
        guard let vocab = llama_model_get_vocab(model) else { throw LlamaError.failedToLoad }
        llama_memory_clear(llama_get_memory(ctx), true)

        let tokens = Self.tokenize(prompt, vocab: vocab)
        guard !tokens.isEmpty else { return "" }
        try Self.evalTokens(tokens, ctx: ctx, batchSize: cfg.batchSize)

        var output = ""
        var nPast = Int32(tokens.count)
        var batch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch) }

        for _ in 0..<cfg.maxTokens {
            let tok = llama_sampler_sample(sampler, ctx, -1)
            llama_sampler_accept(sampler, tok)
            if llama_vocab_is_eog(vocab, tok) { break }
            output += Self.tokenToPiece(tok, vocab: vocab)
            Self.batchClear(&batch)
            Self.batchAdd(&batch, token: tok, pos: nPast, seqIDs: [0], logits: true)
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

            // Reserve our slot before the producer task starts. While
            // streamGenerationsInFlight > 0, `unload()` waits — so the
            // ctx/model/sampler pointers stay valid for the whole loop.
            beginStreamGeneration()

            let task = Task { [weak self] in
                defer {
                    // Decrement happens after the Task body finishes
                    // (including normal exit, cancellation, throw).
                    Task { [weak self] in await self?.endStreamGeneration() }
                }
                do {
                    llama_memory_clear(llama_get_memory(ctx), true)
                    let tokens = LlamaContext.tokenize(prompt, vocab: vocab)
                    guard !tokens.isEmpty else { continuation.finish(); return }
                    try LlamaContext.evalTokens(tokens, ctx: ctx, batchSize: cfg.batchSize)

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
                        continuation.yield(LlamaContext.tokenToPiece(tok, vocab: vocab))
                        LlamaContext.batchClear(&batch)
                        LlamaContext.batchAdd(&batch, token: tok, pos: nPast, seqIDs: [0], logits: true)
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

        var tokens = Self.tokenize(text, vocab: vocab)
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
            Self.batchAdd(&batch, token: tok, pos: Int32(i), seqIDs: [0], logits: i == tokens.count - 1)
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

    // These helpers are pure functions over their parameters — they
    // touch no actor state. Declared `static` so they can be called
    // from inside the `generateStream` producer Task without crossing
    // actor isolation (which would require `await` and break the
    // `inout llama_batch` parameter pattern).
#if canImport(llama)
    static func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let n = Int32(text.utf8.count) + 16
        var tokens = [llama_token](repeating: 0, count: Int(n))
        let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, n, true, true)
        guard count >= 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }

    static func tokenToPiece(_ token: llama_token, vocab: OpaquePointer) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buf, 256, 0, false)
        guard n > 0 else { return "" }
        buf[Int(n)] = 0
        return String(cString: buf)
    }

    /// Manually clear a batch (not provided in the C API)
    static func batchClear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }

    /// Manually add a token to a batch (not provided in the C API)
    static func batchAdd(_ batch: inout llama_batch, token: llama_token, pos: llama_pos, seqIDs: [llama_seq_id], logits: Bool) {
        let idx = Int(batch.n_tokens)
        batch.token[idx]    = token
        batch.pos[idx]      = pos
        batch.n_seq_id[idx] = Int32(seqIDs.count)
        // `batch.seq_id[idx]` is double-pointer storage llama.cpp can
        // theoretically return nil for if the batch was init'd with
        // n_seq_max == 0. Guard rather than force-unwrap.
        if let seqIDPtr = batch.seq_id[idx] {
            for (s, sid) in seqIDs.enumerated() {
                seqIDPtr[s] = sid
            }
        }
        batch.logits[idx] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    static func evalTokens(_ tokens: [llama_token], ctx: OpaquePointer, batchSize: Int) throws {
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
