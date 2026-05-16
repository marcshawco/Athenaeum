import Foundation

// MARK: - MLX Service (Staged)
//
// This is the LLMServiceProtocol implementation for the MLX inference engine.
//
// Status: download surface is live, inference runtime is intentionally staged
// behind a thrown error. Adding mlx-swift via SPM and implementing the
// per-method bodies is a separate piece of work; doing it half-baked is worse
// than landing it deliberately. By having the seam in place we can flip
// engines from Settings without breaking the build.

enum MLXServiceError: LocalizedError {
    case runtimeNotEnabled
    case bundleNotInstalled

    var errorDescription: String? {
        switch self {
        case .runtimeNotEnabled:
            return "The MLX inference runtime ships in a future build. The recommended bundle is already downloaded to your Mac — switch back to llama.cpp in Settings ▸ AI Models to use the assistant today."
        case .bundleNotInstalled:
            return "Download the recommended MLX bundle from Settings ▸ AI Models first."
        }
    }
}

final class MLXService: LLMServiceProtocol, @unchecked Sendable {
    private let bundleManager: MLXModelManager

    init(bundleManager: MLXModelManager) {
        self.bundleManager = bundleManager
    }

    // MARK: - Availability

    func isModelAvailable(_ descriptor: LLMModelDescriptor) -> Bool {
        // An MLX role is "available" when the recommended bundle that serves
        // that role is fully installed on disk.
        bundleManager.installedBundles.values.contains { bundle in
            bundle.descriptor.roles.contains(descriptor.role)
        }
    }

    // MARK: - Load / Unload (no-ops until runtime is wired)

    func loadModel(_ descriptor: LLMModelDescriptor) async throws {
        throw MLXServiceError.runtimeNotEnabled
    }

    func unloadModel(_ role: LLMRole) async {
        // Nothing to unload until the runtime is in place.
    }

    // MARK: - Inference

    func generate(role: LLMRole, prompt: String, maxTokens: Int, temperature: Float) async throws -> String {
        throw MLXServiceError.runtimeNotEnabled
    }

    func generateFromImage(imageData: Data, prompt: String, maxTokens: Int) async throws -> String {
        throw MLXServiceError.runtimeNotEnabled
    }

    func generateStream(role: LLMRole, messages: [ChatMessage], maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: MLXServiceError.runtimeNotEnabled)
        }
    }

    func embed(role: LLMRole, text: String) async throws -> [Float] {
        throw MLXServiceError.runtimeNotEnabled
    }
}

// MARK: - Inference Engine Choice

/// User-selectable inference backend. Persisted via @AppStorage in Settings.
enum InferenceEngine: String, CaseIterable, Sendable {
    case llamaCpp = "llama-cpp"
    case mlx = "mlx"

    var displayName: String {
        switch self {
        case .llamaCpp: "llama.cpp"
        case .mlx:      "MLX (Experimental)"
        }
    }

    var summary: String {
        switch self {
        case .llamaCpp:
            return "Default. Works on every Mac. GGUF models, Metal acceleration."
        case .mlx:
            return "Apple silicon only. Faster on long contexts. Runtime ships in a future build."
        }
    }
}
