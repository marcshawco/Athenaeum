import Foundation

// MARK: - LLM Role Definitions

enum LLMRole: String, CaseIterable, Sendable {
    case tagger   // Qwen 2.5       — JSON tag extraction & classification
    case chat     // Mistral v0.3   — RAG document chat
    case vision   // MiniCPM-V      — smart OCR for images / scanned PDFs
}

// MARK: - Model Descriptor

struct LLMModelDescriptor: Sendable {
    let role: LLMRole
    let displayName: String
    let filename: String
    let parameterSize: String
    let quantization: String

    static let defaults: [LLMModelDescriptor] = [
        LLMModelDescriptor(
            role: .tagger,
            displayName: "Qwen 2.5 7B",
            filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
            parameterSize: "7B",
            quantization: "Q4_K_M"
        ),
        LLMModelDescriptor(
            role: .chat,
            displayName: "Mistral v0.3 7B",
            filename: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
            parameterSize: "7B",
            quantization: "Q4_K_M"
        ),
        LLMModelDescriptor(
            role: .vision,
            displayName: "MiniCPM-V 2.6",
            filename: "ggml-model-Q4_K_M.gguf",
            parameterSize: "8B",
            quantization: "Q4_K_M"
        ),
    ]
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

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
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

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
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
            let cfg: LlamaInferenceConfig = descriptor.role == .tagger ? .tagging : .chat
            let ctx = LlamaContext(descriptor: descriptor, modelPath: path, config: cfg)
            try await ctx.load()
            lock.withLock { contexts[descriptor.role] = ctx }
        }

        await MainActor.run { () -> Void in modelManager.loadedModels.insert(descriptor.role) }
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
        // Try LLM-enhanced OCR if vision model is available
        if lock.withLock({ visionContext }) == nil {
            if let descriptor = LLMModelDescriptor.defaults.first(where: { $0.role == .vision }),
               isModelAvailable(descriptor) {
                try? await loadModel(descriptor)
            }
        }
        if let vc = lock.withLock({ visionContext }) {
            // Vision model loaded — use LLM-enhanced OCR (Vision OCR + LLM cleanup)
            return try await vc.extractText(from: imageData, prompt: prompt)
        }

        // No vision model — fall back to native Apple Vision OCR (still excellent)
        return try await nativeOCR.recognizeText(in: imageData)
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
        let ctx = try await contextForRole(role)
        return try await ctx.embed(text)
    }

    // MARK: - Context Management

    private func generationConfig(for role: LLMRole) -> LlamaInferenceConfig {
        switch role {
        case .tagger: .tagging
        case .chat: .chat
        case .vision: .ocr
        }
    }

    private func contextForRole(_ role: LLMRole) async throws -> LlamaContext {
        // Return cached context if already loaded
        if let ctx = lock.withLock({ contexts[role] }) { return ctx }

        // Auto-load if model is available on disk
        guard let descriptor = LLMModelDescriptor.defaults.first(where: { $0.role == role }) else {
            throw LlamaError.modelNotFound("No descriptor for role \(role.rawValue)")
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

        return """
        You are Athenaeum's local document filing assistant. Analyze the document text and return a JSON object with exactly these keys:
        - "title": concise descriptive title (string)
        - "document_type": the single most specific slug from the taxonomy below that describes this document (string). Use kebab-case slug exactly as listed. If nothing fits, use null.
        - "category": the parent category slug from the taxonomy (string). Must be a category from the list. Null only if document_type is null.
        - "tags": 2-6 supporting tag slugs (array of kebab-case strings). Prefer the controlled vocabulary pool before inventing new tags. Do not duplicate the document_type slug here.
        - "correspondent": author, sender, or issuing organization if identifiable (string or null)
        - "date": document date in YYYY-MM-DD format if found in the document (string or null)
        - "summary": 1-2 sentence summary of what the document is and what it accomplishes (string)

        DOCUMENT TAXONOMY (pick document_type from these slugs; pick category from the category slug at the start of each line):
        \(taxonomy)

        SUPPORTING TAG POOL (use for the "tags" array):
        [\(tagList)]

        Rules:
        - Always pick a "document_type" if the text resembles any taxonomy entry, even loosely. Specificity beats vagueness — prefer "lease-agreement" over "contract" if it's a lease.
        - "category" must be the parent category slug of the chosen document_type.
        - Always assign at least two tags in "tags". Use the supporting pool; do not repeat the document_type slug.
        - Respond with ONLY valid JSON. No markdown, no explanation, no trailing commas.

        Document text:
        \(String(text.prefix(4000)))
        """
    }

    // Computed to avoid Swift 6 global actor isolation warning on static stored properties.
    static var ocrPrompt: String {
        "Extract all visible text from this image. Preserve layout and structure. " +
        "Include headers, body text, tables, and any handwritten text. " +
        "Return only the extracted text, no commentary."
    }
}
