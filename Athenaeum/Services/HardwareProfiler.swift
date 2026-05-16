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
}
