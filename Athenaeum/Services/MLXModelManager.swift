import Foundation

// MARK: - MLX Model Management
//
// MLX models from `mlx-community` on Hugging Face are stored as *directories*
// of files (config.json, tokenizer.*, one or more .safetensors shards) rather
// than the single-file GGUF used by llama.cpp. This file defines the bundle
// descriptors, the manager (detect/uninstall), and the multi-file downloader.
//
// The actual MLX *inference runtime* (mlx-swift) is intentionally not wired
// yet — see `MLXService` for the staged interface. The download surface is
// real and operates against live Hugging Face URLs, so once the runtime is
// added the files are already on disk.

// MARK: - Bundle Descriptor

/// One MLX model bundle on Hugging Face — a curated pick that covers an
/// Athenaeum role (or several roles at once).
struct MLXBundleDescriptor: Sendable, Hashable {
    let id: String                  // stable local key, e.g. "qwen-2.5-7b-instruct-4bit"
    let displayName: String         // "Qwen 2.5 7B Instruct — 4-bit MLX"
    let summary: String             // one-line description shown in the UI
    let repoID: String              // HF repo, e.g. "mlx-community/Qwen2.5-7B-Instruct-4bit"
    let revision: String            // git ref — "main" is fine for curated picks
    let expectedSize: Int64         // approximate total bytes (for progress)
    let roles: Set<LLMRole>         // which Athenaeum roles this bundle can serve
    /// Files inside the HF repo we actually need. We hardcode this so we don't
    /// have to call the HF API (no auth, no extra round-trip). If the repo
    /// layout changes we update this list and re-cut the build.
    let files: [String]

    /// The curated "best MLX model for this kind of application" — strong at
    /// instruction following + JSON output (tagging) and document Q&A (chat).
    static let recommended: MLXBundleDescriptor = MLXBundleDescriptor(
        id: "qwen2.5-7b-instruct-4bit-mlx",
        displayName: "Qwen 2.5 7B Instruct · 4-bit MLX",
        summary: "Recommended workhorse for tagging and document Q&A on Apple silicon.",
        repoID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
        revision: "main",
        expectedSize: 4_300_000_000,
        roles: [.tagger, .chat],
        // Order matters for resume-friendly progress: small JSON first, then
        // tokenizer.json (~7 MB), then the big safetensors weights last so
        // that an early cancellation doesn't waste a multi-gigabyte fetch.
        // `model.safetensors.index.json` is *optional* — only sharded repos
        // ship it, and Qwen 2.5 7B 4bit MLX is a single file. The downloader
        // tolerates 404s for files in its `optionalFiles` set.
        files: [
            "config.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "tokenizer.json",
            "model.safetensors.index.json",   // optional (single-file repos 404)
            "model.safetensors",
        ]
    )

    static let all: [MLXBundleDescriptor] = [.recommended]
}

// MARK: - Manager

@Observable
final class MLXModelManager {
    /// Bundles currently installed on disk, keyed by bundle id.
    private(set) var installedBundles: [String: InstalledBundle] = [:]

    struct InstalledBundle: Sendable {
        let descriptor: MLXBundleDescriptor
        let directory: URL
        let totalBytes: Int64
    }

    /// Root directory for MLX bundles. Sibling of the GGUF Models directory so
    /// they don't intermingle.
    var bundlesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Athenaeum/MLXBundles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func directory(for descriptor: MLXBundleDescriptor) -> URL {
        bundlesDirectory.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    /// Files we tolerate being absent (single-file MLX repos return 404 for
    /// the index, for example). Must match `MLXBundleDownloader.optionalFiles`.
    private static let optionalFiles: Set<String> = [
        "model.safetensors.index.json",
        "added_tokens.json",
        "merges.txt",
        "chat_template.jinja",
    ]

    /// True when every *required* file in `descriptor.files` exists on disk.
    /// Optional files (404-tolerated) don't gate completion.
    func isFullyInstalled(_ descriptor: MLXBundleDescriptor) -> Bool {
        let dir = directory(for: descriptor)
        for relative in descriptor.files where !Self.optionalFiles.contains(relative) {
            let path = dir.appendingPathComponent(relative).path
            if !FileManager.default.fileExists(atPath: path) { return false }
        }
        return true
    }

    /// Scan disk for installed bundles and refresh `installedBundles`.
    func scan() {
        installedBundles.removeAll()
        for descriptor in MLXBundleDescriptor.all where isFullyInstalled(descriptor) {
            let dir = directory(for: descriptor)
            let size = directorySize(at: dir)
            installedBundles[descriptor.id] = InstalledBundle(
                descriptor: descriptor,
                directory: dir,
                totalBytes: size
            )
        }
    }

    @discardableResult
    func uninstall(_ descriptor: MLXBundleDescriptor) -> Bool {
        let dir = directory(for: descriptor)
        do {
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
            installedBundles.removeValue(forKey: descriptor.id)
            NotificationCenter.default.post(name: .mlxBundlesDidChange, object: nil)
            return true
        } catch {
            return false
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
               let bytes = values.totalFileAllocatedSize {
                total += Int64(bytes)
            }
        }
        return total
    }
}

// Notification.Name.mlxBundlesDidChange is declared centrally in
// `AthenaeumApp.swift` alongside the rest of the app-wide names.
