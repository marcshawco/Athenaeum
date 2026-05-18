import Foundation

// MARK: - LLM Role Definitions

enum LLMRole: String, CaseIterable, Sendable {
    case tagger     // Qwen 2.5 14B — JSON tag extraction & classification
    case chat       // Qwen 2.5 14B — RAG document chat (shares Qwen 14B with tagger)
    case embedding  // Nomic Embed Text v1.5 — purpose-built retrieval embeddings
    case vision     // MiniCPM-V 2.6 — smart OCR for images / scanned PDFs
}

// MARK: - Model Descriptor

struct LLMModelDescriptor: Sendable {
    let role: LLMRole
    let displayName: String
    let filename: String
    let parameterSize: String
    let quantization: String

    /// Active descriptor list — adapts to the host Mac's tier so we don't
    /// try to load Qwen 14B on an 8 GB MacBook Air. See `HardwareProfiler`
    /// for tier detection logic and `descriptors(for:)` below for the
    /// per-tier lineups.
    static var defaults: [LLMModelDescriptor] {
        descriptors(for: HardwareProfiler.activeTier)
    }

    /// Tier-specific model lineup. Lighter Macs get smaller models;
    /// heavier Macs unlock the bigger ones. Embedding (Nomic, 84 MB)
    /// is the same everywhere because it's tiny and quality matters.
    static func descriptors(for tier: HardwareTier) -> [LLMModelDescriptor] {
        let embedding = LLMModelDescriptor(
            role: .embedding,
            displayName: "Nomic Embed Text v1.5",
            filename: "nomic-embed-text-v1.5.Q4_K_M.gguf",
            parameterSize: "137M",
            quantization: "Q4_K_M"
        )

        let vision = LLMModelDescriptor(
            role: .vision,
            displayName: "MiniCPM-V 2.6",
            filename: "ggml-model-Q4_K_M.gguf",
            parameterSize: "8B",
            quantization: "Q4_K_M"
        )

        switch tier {
        case .low:
            // 8 GB Macs — Qwen 3B (~2 GB) for both tagger and chat,
            // skip the 5 GB MiniCPM-V (Apple Vision OCR is still
            // excellent for printed text).
            return [
                LLMModelDescriptor(role: .tagger,
                                   displayName: "Qwen 2.5 3B Instruct",
                                   filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
                                   parameterSize: "3B",
                                   quantization: "Q4_K_M"),
                LLMModelDescriptor(role: .chat,
                                   displayName: "Qwen 2.5 3B Instruct",
                                   filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
                                   parameterSize: "3B",
                                   quantization: "Q4_K_M"),
                embedding,
            ]
        case .standard:
            // 16 GB Macs — Qwen 7B (~4.7 GB) plus MiniCPM-V (~5 GB).
            return [
                LLMModelDescriptor(role: .tagger,
                                   displayName: "Qwen 2.5 7B Instruct",
                                   filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                                   parameterSize: "7B",
                                   quantization: "Q4_K_M"),
                LLMModelDescriptor(role: .chat,
                                   displayName: "Qwen 2.5 7B Instruct",
                                   filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                                   parameterSize: "7B",
                                   quantization: "Q4_K_M"),
                embedding,
                vision,
            ]
        case .high, .workstation:
            // 24+ GB Macs — Qwen 14B (~9 GB) plus MiniCPM-V (~5 GB).
            // Workstation is identical for now; reserved for a 32B
            // option if we ever ship one.
            return [
                LLMModelDescriptor(role: .tagger,
                                   displayName: "Qwen 2.5 14B Instruct",
                                   filename: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
                                   parameterSize: "14B",
                                   quantization: "Q4_K_M"),
                LLMModelDescriptor(role: .chat,
                                   displayName: "Qwen 2.5 14B Instruct",
                                   filename: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
                                   parameterSize: "14B",
                                   quantization: "Q4_K_M"),
                embedding,
                vision,
            ]
        }
    }

    /// Distinct descriptors keyed by filename, preserving order. Multiple
    /// roles can map to the same file (tagger + chat both run on Qwen 14B);
    /// Model Status uses this list to render one tile per actual download.
    static var uniqueByFilename: [LLMModelDescriptor] {
        var seen = Set<String>()
        return defaults.filter { seen.insert($0.filename).inserted }
    }

    /// All roles served by a given filename. Lets the UI describe a single
    /// tile in terms of every job it covers ("tagger + chat" instead of
    /// just "tagger").
    static func roles(forFilename filename: String) -> [LLMRole] {
        defaults.filter { $0.filename == filename }.map(\.role)
    }
}

// MARK: - LLM Service Protocol

protocol LLMServiceProtocol: Sendable {
    func isModelAvailable(_ descriptor: LLMModelDescriptor) -> Bool
    func loadModel(_ descriptor: LLMModelDescriptor) async throws
    func unloadModel(_ role: LLMRole) async
    func generate(role: LLMRole, prompt: String, maxTokens: Int, temperature: Float) async throws -> String
    func generateFromImage(imageData: Data, prompt: String, maxTokens: Int) async throws -> String
    func generateStream(role: LLMRole, messages: [ChatMessage], maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error>
    func embed(role: LLMRole, text: String) async throws -> [Float]
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    // `nonisolated` so this value type can be constructed off the main
    // actor — used by the `nonisolated` `StoredMessage.chatMessage` round-
    // trip when persisted chats decode on a background context.
    nonisolated init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }

    /// Explicit-id initializer for round-tripping persisted messages out of
    /// `ChatConversation.messagesJSON` so `id` stays stable across launches
    /// (matters for per-message source dictionaries and SwiftUI list IDs).
    nonisolated init(id: UUID, role: ChatRole, content: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum ChatRole: String, Sendable, Codable {
    case system, user, assistant
}

// MARK: - Model Manager

@Observable
final class ModelManager {
    private(set) var availableModels: [LLMRole: LLMModelDescriptor] = [:]
    var loadedModels: Set<LLMRole> = []
    private(set) var isLoading: [LLMRole: Bool] = [:]
    private(set) var error: String?
    /// File size on disk for each detected model (in bytes), keyed by role.
    private(set) var modelFileSizes: [LLMRole: Int64] = [:]

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Athenaeum/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Re-scan the models directory for known GGUF files and refresh sizes.
    /// Also picks up files placed manually by the user.
    func scanForModels() {
        availableModels.removeAll()
        modelFileSizes.removeAll()
        for descriptor in LLMModelDescriptor.defaults {
            let path = modelsDirectory.appendingPathComponent(descriptor.filename)
            if FileManager.default.fileExists(atPath: path.path) {
                availableModels[descriptor.role] = descriptor
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
                   let size = attrs[.size] as? NSNumber {
                    modelFileSizes[descriptor.role] = size.int64Value
                }
            }
        }
    }

    func modelPath(for descriptor: LLMModelDescriptor) -> URL {
        modelsDirectory.appendingPathComponent(descriptor.filename)
    }

    /// Uninstall a model by deleting its GGUF file from disk.
    /// Caller should unload the model first (see `LocalLLMService.unloadModel`).
    @discardableResult
    func uninstallModel(_ descriptor: LLMModelDescriptor) -> Bool {
        let path = modelPath(for: descriptor)
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            availableModels.removeValue(forKey: descriptor.role)
            modelFileSizes.removeValue(forKey: descriptor.role)
            loadedModels.remove(descriptor.role)
            error = nil
            NotificationCenter.default.post(name: .modelsDidChange, object: nil)
            return true
        } catch let err {
            error = "Could not uninstall \(descriptor.displayName): \(err.localizedDescription)"
            return false
        }
    }
}

// MARK: - Real Local LLM Service

/// Production implementation backed by llama.cpp via LlamaContext actors.
final class LocalLLMService: LLMServiceProtocol, @unchecked Sendable {
    private let modelManager: ModelManager

    // One LlamaContext actor per role, lazily created
    private var contexts: [LLMRole: LlamaContext] = [:]
    private var visionContext: LlamaVisionContext?
    private let nativeOCR = VisionOCRService()
    private let lock = NSLock()

    /// Set when the hardware tier changes (or any other event that
    /// shifts `LlamaInferenceConfig` values). Active requests run to
    /// completion on the existing contexts; the next request after this
    /// flag is set triggers `purgeStaleContextsIfNeeded()`, which
    /// unloads every cached context so the next load picks up the
    /// fresh config (n_ctx, GPU layers, threads).
    private var hasStaleConfigs = false

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Mark every loaded context as needing a fresh reload with the
    /// latest `LlamaInferenceConfig`. Called by ContentView on
    /// `.hardwareTierDidChange`. Cheap and synchronous — the actual
    /// unload happens lazily on the next inference request.
    func markAllContextsStale() {
        lock.withLock { hasStaleConfigs = true }
    }

    func isModelAvailable(_ descriptor: LLMModelDescriptor) -> Bool {
        FileManager.default.fileExists(atPath: modelManager.modelPath(for: descriptor).path)
    }

    func loadModel(_ descriptor: LLMModelDescriptor) async throws {
        let path = modelManager.modelPath(for: descriptor)

        if descriptor.role == .vision {
            let vc = LlamaVisionContext(descriptor: descriptor, modelPath: path)
            try await vc.load()
            lock.withLock { visionContext = vc }
        } else {
            let cfg: LlamaInferenceConfig = loadConfig(for: descriptor.role)
            let ctx = LlamaContext(descriptor: descriptor, modelPath: path, config: cfg)
            try await ctx.load()
            lock.withLock { contexts[descriptor.role] = ctx }
        }

        await MainActor.run { () -> Void in modelManager.loadedModels.insert(descriptor.role) }
    }

    /// Load-time inference config (context size, GPU layers, batch size).
    /// Per-call sampling overrides live in `generationConfig(for:)`.
    private func loadConfig(for role: LLMRole) -> LlamaInferenceConfig {
        switch role {
        case .tagger:    .tagging
        case .chat:      .chat
        case .embedding: .embedding
        case .vision:    .ocr
        }
    }

    func unloadModel(_ role: LLMRole) async {
        if role == .vision {
            if let vc = lock.withLock({ visionContext }) {
                await vc.unload()
                lock.withLock { visionContext = nil }
            }
        } else {
            if let ctx = lock.withLock({ contexts[role] }) {
                await ctx.unload()
                lock.withLock { _ = contexts.removeValue(forKey: role) }
            }
        }
        await MainActor.run { () -> Void in modelManager.loadedModels.remove(role) }
    }

    func generate(role: LLMRole, prompt: String, maxTokens: Int, temperature: Float) async throws -> String {
        let ctx = try await contextForRole(role)
        var cfg = generationConfig(for: role)
        cfg.maxTokens = maxTokens
        cfg.temperature = temperature
        return try await ctx.generate(prompt: prompt, config: cfg)
    }

    func generateFromImage(imageData: Data, prompt: String, maxTokens: Int) async throws -> String {
        // Lazy-reload hook: same as `contextForRole(_:)`. Drop any stale
        // vision context (and any sibling text contexts) so the load
        // below uses the latest `LlamaInferenceConfig`.
        await purgeStaleContextsIfNeeded()

        // Try LLM-enhanced OCR if vision model is available. Funnel
        // concurrent first-OCR callers through a single in-flight load
        // task — without this gate, two callers can both observe
        // `visionContext == nil` and both call `loadModel`, double-
        // loading the 5 GB MiniCPM-V file and trashing RAM.
        if lock.withLock({ visionContext }) == nil {
            try? await loadVisionContextIfAvailable()
        }
        if let vc = lock.withLock({ visionContext }) {
            // Vision model loaded — use LLM-enhanced OCR (Vision OCR + LLM cleanup)
            return try await vc.extractText(from: imageData, prompt: prompt)
        }

        // No vision model — fall back to native Apple Vision OCR (still excellent)
        return try await nativeOCR.recognizeText(in: imageData)
    }

    /// Single-flight vision-context loader. Multiple concurrent callers
    /// share one in-progress `Task` instead of each kicking off their
    /// own multi-gigabyte mmap.
    private var visionLoadTask: Task<Void, Error>?

    private func loadVisionContextIfAvailable() async throws {
        // Read the existing task under lock so two callers race-free
        // share the in-flight one.
        let existing: Task<Void, Error>? = lock.withLock { visionLoadTask }
        if let existing {
            try await existing.value
            return
        }
        let task = Task<Void, Error> {
            defer {
                lock.withLock { _ = visionLoadTask; visionLoadTask = nil }
            }
            guard let descriptor = LLMModelDescriptor.defaults.first(where: { $0.role == .vision }),
                  isModelAvailable(descriptor) else { return }
            try await loadModel(descriptor)
        }
        lock.withLock { visionLoadTask = task }
        try await task.value
    }

    func generateStream(role: LLMRole, messages: [ChatMessage], maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let ctx = try await self.contextForRole(role)
                    var cfg = self.generationConfig(for: role)
                    cfg.maxTokens = maxTokens
                    cfg.temperature = temperature
                    let stream = await ctx.generateStream(messages: messages, config: cfg)
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func embed(role: LLMRole, text: String) async throws -> [Float] {
        // RAGService prepends Nomic's task prefix ("search_document: " or
        // "search_query: "). If a stray caller forgot, default to the
        // document prefix so we never embed bare text against this model.
        let ctx = try await contextForRole(role)
        let prepared: String = {
            guard role == .embedding else { return text }
            if text.hasPrefix("search_document:") || text.hasPrefix("search_query:") {
                return text
            }
            return "search_document: " + text
        }()
        return try await ctx.embed(prepared)
    }

    // MARK: - Context Management

    private func generationConfig(for role: LLMRole) -> LlamaInferenceConfig {
        switch role {
        case .tagger:    .tagging
        case .chat:      .chat
        case .embedding: .embedding
        case .vision:    .ocr
        }
    }

    /// Drain the cache when configs were marked stale (e.g. by a
    /// hardware-tier change). Active requests are already mid-flight on
    /// the actors; since `LlamaContext` and `LlamaVisionContext` are
    /// actors with serial executors, the `unload()` calls we await
    /// queue *behind* any in-flight work and run once it completes.
    /// `unload()` is idempotent (guarded by `isLoaded`), so re-unloading
    /// a shared context that's already torn down is a no-op.
    private func purgeStaleContextsIfNeeded() async {
        let shouldPurge = lock.withLock { () -> Bool in
            guard hasStaleConfigs else { return false }
            hasStaleConfigs = false
            return true
        }
        guard shouldPurge else { return }

        // Snapshot unique context references (tagger + chat can share a
        // single LlamaContext when they resolve to the same file).
        // Dedupe so we don't await unload on the same actor twice.
        let snapshot: ([LlamaContext], LlamaVisionContext?, [LLMRole]) = lock.withLock {
            var seen = Set<ObjectIdentifier>()
            var uniqueContexts: [LlamaContext] = []
            for ctx in contexts.values where seen.insert(ObjectIdentifier(ctx)).inserted {
                uniqueContexts.append(ctx)
            }
            let removedRoles = Array(contexts.keys)
            let vc = visionContext
            contexts.removeAll()
            visionContext = nil
            return (uniqueContexts, vc, removedRoles)
        }

        for ctx in snapshot.0 {
            await ctx.unload()
        }
        if let vc = snapshot.1 {
            await vc.unload()
        }

        let roles = snapshot.2
        let hadVision = snapshot.1 != nil
        if !roles.isEmpty || hadVision {
            await MainActor.run { () -> Void in
                for role in roles { modelManager.loadedModels.remove(role) }
                if hadVision { modelManager.loadedModels.remove(.vision) }
            }
        }
    }

    private func contextForRole(_ role: LLMRole) async throws -> LlamaContext {
        // Lazy-reload hook: if any tier-driven config (n_ctx, GPU layers,
        // threads) has changed since this context was loaded, drop every
        // cached context now so the load path below picks up the new
        // `LlamaInferenceConfig` from UserDefaults.
        await purgeStaleContextsIfNeeded()

        // Return cached context if already loaded for this role.
        if let ctx = lock.withLock({ contexts[role] }) { return ctx }

        guard let descriptor = LLMModelDescriptor.defaults.first(where: { $0.role == role }) else {
            throw LlamaError.modelNotFound("No descriptor for role \(role.rawValue)")
        }

        // Share contexts across roles that point at the same model file.
        // Tagger and chat both resolve to Qwen 14B — loading the same weights
        // twice would cost ~5 GB extra in RAM. When any role with a matching
        // filename is already loaded, route this role to that context.
        if let shared = lock.withLock({ sharedContextLocked(for: descriptor.filename) }) {
            lock.withLock { contexts[role] = shared }
            await MainActor.run { () -> Void in modelManager.loadedModels.insert(role) }
            return shared
        }

        guard isModelAvailable(descriptor) else {
            throw LlamaError.modelNotFound(
                "\(descriptor.displayName) not installed. Download it from Model Status."
            )
        }

        try await loadModel(descriptor)

        guard let ctx = lock.withLock({ contexts[role] }) else {
            throw LlamaError.failedToLoad
        }
        return ctx
    }

    /// Find any already-loaded context whose role descriptor has the given
    /// filename. Caller must hold `lock`. Returns nil if no role with this
    /// filename is currently loaded.
    private func sharedContextLocked(for filename: String) -> LlamaContext? {
        for (loadedRole, ctx) in contexts {
            if let d = LLMModelDescriptor.defaults.first(where: { $0.role == loadedRole }),
               d.filename == filename {
                return ctx
            }
        }
        return nil
    }
}

// MARK: - Tagging Prompts

enum TaggingPrompts {
    static func classifyDocument(text: String, existingTags: [String]) -> String {
        let availableTags = Array(Set(Tag.builtInPool + existingTags)).sorted()
        let tagList = availableTags.joined(separator: ", ")

        // Compact representation of the 500-type taxonomy: one line per category
        // listing its type slugs. This gives the local LLM a structured menu of
        // canonical document types to pick from.
        let taxonomy = DocumentTaxonomy.categories.map { cat in
            "- \(cat.slug): " + cat.types.map(\.slug).joined(separator: ", ")
        }.joined(separator: "\n")

        // Pull more text into the prompt — 4 K was too little for invoices
        // with boilerplate at the top. 8 K still fits comfortably alongside
        // the system prompt + JSON output budget on Qwen 7B/14B Q4_K_M.
        let body = String(text.prefix(8000))

        // Optional user-authored "About You" note from Settings → AI Models.
        // When set, gives the tagger a sense of the user's role and frequent
        // filing domains so ambiguous documents get tagged in line with how
        // the user actually thinks about them.
        let aboutTheUser: String = {
            let raw = (UserDefaults.standard.string(forKey: "aiContextNote") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return "" }
            return """

        ABOUT THE USER (standing context — use it to disambiguate the document, not to override THE ONE RULE):
        \(raw)

        """
        }()

        return """
        You are ATHENS's document filing assistant. Tag the document below.\(aboutTheUser)

        THE ONE RULE that overrides everything else:
        EVERY tag must point to a specific phrase you can quote from the document. If a single mention of the word "tax" is the only thing supporting a `tax` tag, do NOT use it. Tags describe what the document IS, not topics the document casually mentions.

        Common failure modes you must avoid:
        - A resume that mentions a previous employer in "tax preparation" is NOT tagged `tax`. It's tagged `resume`, `career`, and the industry/role (e.g. `loss-prevention`, `hospitality`).
        - A brand strategy document that mentions "lease terms for retail locations" is NOT tagged `lease`. It's tagged `brand-strategy`, `marketing-strategy`, plus the relevant industry (e.g. `fashion`, `retail`).
        - A lab report mentioning a "billing inquiry" is NOT tagged `bill`. It's tagged `lab-results`, `medical`.

        Return ONLY valid JSON (no markdown, no prose) with these keys:
        - "title": 4-8 word descriptive title. Prefer the document's own title.
        - "document_type": the single most specific slug from the TAXONOMY that describes what the document IS. kebab-case, exactly as listed. null if nothing fits — do not invent.
        - "category": the parent category slug of the chosen document_type. null only if document_type is null.
        - "tags": 2-5 tag slugs. Prefer slugs from the SUPPORTING TAG POOL below — those are the anchors we want for consistency. If nothing in the pool fits a primary subject, coin a new slug yourself, but use the pool's terminology where it applies (e.g. `health-checkup` not `medical-appointment` when `health` is the anchor). Each tag MUST be the primary subject of the document, not a side mention. Prefer fewer accurate tags over more.
        - "correspondent": author/sender/issuing org if clearly identifiable, else null.
        - "date": document date in YYYY-MM-DD if EXPLICITLY written, else null. Do not infer.
        - "summary": 1-2 sentence plain description of what this document is.

        DOCUMENT TAXONOMY (pick document_type from these slugs; pick category from the category slug at the start of each line):
        \(taxonomy)

        SUPPORTING TAG POOL (broad anchors — prefer these for consistency, but you may coin a new well-formed slug if a primary subject isn't anchored here):
        [\(tagList)]

        SLUG SHAPE (applies to any tag you coin yourself, not the pool):
        - lowercase ASCII, words separated by single hyphens
        - 2 to 40 characters
        - no leading/trailing/doubled hyphens
        - at least one letter (no digit-only slugs)

        EXAMPLES (note how the tags describe the document's identity, never side mentions):

        Example A — a 2-page resume for a hotel loss-prevention manager:
        {"title":"Marcus Shaw Loss Prevention Resume","document_type":"resume","category":"employment","tags":["resume","career","loss-prevention","hospitality","security"],"correspondent":"Marcus Shaw","date":null,"summary":"Resume for a hotel loss prevention manager with 8 years at Marriott properties."}

        Example B — a brand-strategy white paper about a fashion incubation model:
        {"title":"Chaz Jordan Brand Incubation Strategy Analysis","document_type":"whitepaper","category":"business","tags":["brand-strategy","marketing-strategy","fashion","case-study"],"correspondent":null,"date":null,"summary":"Analytical whitepaper on a fashion designer's brand incubation and luxury market disruption strategy."}

        Example C — an IRS Form 1040 with W-2 attached:
        {"title":"2025 Federal Income Tax Return Form 1040","document_type":"irs-form-1040","category":"tax","tags":["tax-return","1040","w-2","irs"],"correspondent":"Internal Revenue Service","date":"2026-04-15","summary":"Filed 2025 federal income tax return with W-2 wage attachment."}

        HARD RULES:
        - Specificity beats vagueness — "lease-agreement" not "contract" when it's a lease; "irs-form-1040" not "tax" when it's a 1040.
        - Never tag based on filename or extension. Only the document body counts.
        - Prefer pool tags. Coin a new slug only when no pool tag describes a primary subject of the document, and keep it broad rather than micro (e.g. `network-security` not `network-security-implementation-best-practices`).
        - When in doubt, return FEWER tags. Two accurate tags beat five mixed ones.
        - If the document is too short/generic to classify, return null for document_type/category and only the most defensible tags.
        - Respond with ONLY valid JSON. No markdown fences, no explanation, no trailing commas.
        - Do NOT continue, summarize, or echo the document text. Your entire job is to emit the JSON object once and stop.

        DOCUMENT TEXT (read this, then produce the JSON):
        \(body)

        === END OF DOCUMENT ===

        Now respond with the single JSON object describing the document above. Begin your response with `{` and end with `}`. Output nothing else.
        """
    }

    /// Prompt the model to invent a clean, file-system-safe name for a
    /// document based on its actual contents. Used by the right-click
    /// "Rename with AI" action.
    static func renameDocument(
        text: String,
        originalFilename: String,
        documentType: String? = nil,
        category: String? = nil
    ) -> String {
        let body = String(text.prefix(6000))
        let typeHint = documentType.map { "Known type: \($0)\n" } ?? ""
        let categoryHint = category.map { "Known category: \($0)\n" } ?? ""

        return """
        You are ATHENS's file-naming assistant. Propose a clean, descriptive filename for the document below. The user is trying to replace a junk name like "Scanned Document (2).pdf" with something they can find in Finder six months from now.

        \(typeHint)\(categoryHint)Current filename: \(originalFilename)

        FORMAT — IMPORTANT:
        - Plain text, no file extension.
        - 4 to 10 words.
        - Capitalize the major words (Title Case).
        - Include the most identifying details from the document: a date if present (e.g. "Mar 2026"), an issuer or party ("Kaiser"), a document kind ("EOB", "Lease", "W-2"), and any unique identifier if helpful.
        - No special characters except hyphens between words is fine. No slashes, colons, asterisks, question marks, pipes, brackets.
        - Do not add quotes, prose, or explanation. Output ONLY the bare filename string.

        Document text:
        \(body)
        """
    }

    // Computed to avoid Swift 6 global actor isolation warning on static stored properties.
    static var ocrPrompt: String {
        "Extract all visible text from this image. Preserve layout and structure. " +
        "Include headers, body text, tables, and any handwritten text. " +
        "Return only the extracted text, no commentary."
    }
}
