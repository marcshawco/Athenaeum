import Foundation

// MARK: - Hardware Tier
//
// Athenaeum's AI stack scales to match the host Mac. A 64 GB M-series
// workstation can comfortably hold Qwen 2.5 14B; an 8 GB MacBook Air
// can barely load it without swapping the SSD to death. Detecting the
// available unified memory at launch lets us pick a sensible default
// lineup per machine, while a user-visible override lets power users
// force a smaller or larger tier.
//
// This is a documentation app, not a benchmark — picking the heaviest
// model that *fits* is the wrong default. Pick the lightest model that
// does the job well at this machine's tier.

enum HardwareTier: String, CaseIterable, Sendable, Codable {
    /// 8 GB Apple Silicon Macs. Qwen 2.5 3B + Nomic, no vision LLM
    /// (falls back to Apple Vision OCR, still excellent).
    case low
    /// 16 GB Macs. Qwen 2.5 7B + Nomic + MiniCPM-V 2.6.
    case standard
    /// 24-48 GB Macs. Qwen 2.5 14B + Nomic + MiniCPM-V 2.6.
    case high
    /// 64+ GB workstations. Same lineup as high today; reserved for a
    /// future bigger model (e.g. Qwen 32B) if we ever ship it.
    case workstation

    /// Friendly name for UI.
    var displayName: String {
        switch self {
        case .low:         "Compact"
        case .standard:    "Standard"
        case .high:        "Performance"
        case .workstation: "Workstation"
        }
    }

    /// One-line rationale shown alongside the badge.
    var rationale: String {
        switch self {
        case .low:
            "8 GB unified memory. Qwen 2.5 3B handles tagging and chat with headroom for the rest of the system. Vision OCR falls back to Apple's native engine, which is still excellent for printed text."
        case .standard:
            "16 GB unified memory. Qwen 2.5 7B for tagging and chat, plus MiniCPM-V for enhanced OCR on scanned PDFs."
        case .high:
            "24 GB or more. Qwen 2.5 14B for the sharpest tagging and chat, plus MiniCPM-V for enhanced OCR."
        case .workstation:
            "64 GB or more. Same lineup as Performance — Qwen 14B is already in the sweet spot for document work. Bigger models exist but don't measurably help here."
        }
    }

    // MARK: - Tier-aware tunables
    //
    // The tier doesn't just pick which model file to load; it sets the
    // shape of every retrieval-augmented chat. Lower tiers shrink the
    // chunk size, top-K, and per-prompt char budget so an 8 GB Mac stays
    // responsive; higher tiers grow them so a 64 GB workstation actually
    // uses its memory.
    //
    // `contextSize` must stay in {2048, 4096, 8192} — the value flows
    // into `LlamaInferenceConfig.configuredContextSize`, which clamps
    // anything else to 4096.

    struct Tunables: Sendable, Equatable {
        // Inference
        let contextSize: Int     // n_ctx for chat/tagging
        let gpuLayers: Int       // -1 = all on Metal; 0 = CPU only
        // RAG indexing
        let chunkSize: Int       // words per chunk
        let chunkOverlap: Int    // word overlap between consecutive chunks
        // RAG retrieval
        let ragTopK: Int                          // chunks per chat turn
        let perChunkCharBudget: Int               // max chars per retrieved chunk in prompt
        let totalContextCharBudget: Int           // total prompt chars across all chunks
        let retrievalOverfetchMultiplier: Int     // over-fetch factor on top-K
        let perDocLimit: Int                      // diversity cap: max chunks from one doc
    }

    var tunables: Tunables {
        switch self {
        case .low:
            return Tunables(
                contextSize: 4096, gpuLayers: -1,
                chunkSize: 384, chunkOverlap: 48,
                ragTopK: 4,
                perChunkCharBudget: 800,
                totalContextCharBudget: 4500,
                retrievalOverfetchMultiplier: 5,
                perDocLimit: 2
            )
        case .standard:
            return Tunables(
                contextSize: 4096, gpuLayers: -1,
                chunkSize: 512, chunkOverlap: 64,
                ragTopK: 6,
                perChunkCharBudget: 1200,
                totalContextCharBudget: 8000,
                retrievalOverfetchMultiplier: 6,
                perDocLimit: 3
            )
        case .high:
            return Tunables(
                contextSize: 8192, gpuLayers: -1,
                chunkSize: 640, chunkOverlap: 96,
                ragTopK: 8,
                perChunkCharBudget: 1500,
                totalContextCharBudget: 12000,
                retrievalOverfetchMultiplier: 6,
                perDocLimit: 3
            )
        case .workstation:
            return Tunables(
                contextSize: 8192, gpuLayers: -1,
                chunkSize: 768, chunkOverlap: 128,
                ragTopK: 10,
                perChunkCharBudget: 1800,
                totalContextCharBudget: 16000,
                retrievalOverfetchMultiplier: 8,
                perDocLimit: 4
            )
        }
    }
}

// MARK: - Hardware Profiler

enum HardwareProfiler {
    /// User-defaults key that lets a user override the auto-detected tier.
    /// Stored as a `HardwareTier.rawValue` string or `"auto"`.
    static let overrideKey = "hardwareTierOverride"

    /// Total physical memory in gigabytes, rounded to one decimal.
    static var totalMemoryGB: Double {
        let bytes = Double(ProcessInfo.processInfo.physicalMemory)
        return (bytes / 1_073_741_824 * 10).rounded() / 10
    }

    /// Active tier — either the user's override, or the auto-detected
    /// tier if the override is missing or set to "auto".
    static var activeTier: HardwareTier {
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           raw != "auto",
           let forced = HardwareTier(rawValue: raw) {
            return forced
        }
        return detected
    }

    /// Auto-detected tier based on physical memory. Ignores the override.
    static var detected: HardwareTier {
        let gb = totalMemoryGB
        switch gb {
        case ..<12:  return .low
        case ..<20:  return .standard
        case ..<40:  return .high
        default:     return .workstation
        }
    }

    /// Whether the user has explicitly overridden the auto-detected tier.
    static var isOverridden: Bool {
        guard let raw = UserDefaults.standard.string(forKey: overrideKey),
              raw != "auto" else { return false }
        return HardwareTier(rawValue: raw) != nil
    }

    /// Tunables resolved from the currently active tier.
    static var activeTunables: HardwareTier.Tunables {
        activeTier.tunables
    }

    /// Push the active tier's tunables into `UserDefaults` so every
    /// downstream reader — `LlamaInferenceConfig` (n_ctx, GPU layers),
    /// `RAGService.chunkSettings`, `ChatView.ragTopK` — picks them up on
    /// next read. Called by the Settings tier picker `onChange` and once
    /// at first launch so a fresh install starts with the right shape
    /// for the host Mac.
    ///
    /// Models already loaded into memory keep their captured `n_ctx`
    /// until they're reloaded; `NotificationCenter.modelsDidChange` is
    /// posted separately by the caller so observers can refresh.
    @discardableResult
    static func applyTunablesForActiveTier() -> HardwareTier.Tunables {
        let t = activeTunables
        let d = UserDefaults.standard
        d.set(t.contextSize,  forKey: "contextSize")
        d.set(t.gpuLayers,    forKey: "maxGPULayers")
        d.set(t.chunkSize,    forKey: "chunkSize")
        d.set(t.chunkOverlap, forKey: "chunkOverlap")
        d.set(t.ragTopK,      forKey: "ragTopK")
        return t
    }
}
