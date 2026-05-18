import Foundation
import CryptoKit

// MARK: - Model Downloader
// Downloads GGUF models from HuggingFace Hub with progress tracking,
// resume support, redirect-host allowlisting, and optional per-descriptor
// SHA-256 integrity verification.

/// Hostnames whose 30x redirects we follow. Hugging Face uses a
/// CloudFront-fronted CDN for large LFS files; everything else is
/// rejected so a hijacked redirect can't ship a poisoned model.
private let allowedRedirectHosts: Set<String> = [
    "huggingface.co",
    "cdn-lfs.huggingface.co",
    "cdn-lfs-us-1.huggingface.co",
    "cdn-lfs-eu-1.huggingface.co",
]
private let allowedRedirectSuffixes: [String] = [
    ".huggingface.co",
    ".hf.co",
    ".cloudfront.net",
]

func isAllowedRedirectHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    if allowedRedirectHosts.contains(host) { return true }
    return allowedRedirectSuffixes.contains(where: { host.hasSuffix($0) })
}

@Observable
final class ModelDownloader {
    private(set) var downloads: [LLMRole: DownloadState] = [:]
    private var activeTasks: [LLMRole: URLSessionDownloadTask] = [:]
    private var cancelledTaskIDs: Set<Int> = []
    private let modelsDirectory: URL
    private var _session: URLSession?
    private let downloadDelegate = DownloadDelegate()

    private var session: URLSession {
        if let existing = _session { return existing }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        let s = URLSession(configuration: config, delegate: downloadDelegate, delegateQueue: nil)
        _session = s
        return s
    }

    struct DownloadState: Sendable {
        var status: Status
        var progress: Double
        var bytesWritten: Int64
        var totalBytes: Int64
        var speed: String // e.g. "12.5 MB/s"

        enum Status: String, Sendable {
            case idle
            case downloading
            case paused
            case completed
            case failed
            case verifying
        }

        static let idle = DownloadState(status: .idle, progress: 0, bytesWritten: 0, totalBytes: 0, speed: "")
    }

    // MARK: - HuggingFace Model Registry

    struct HFModelInfo: Sendable {
        let role: LLMRole
        let repoID: String
        let filename: String
        let expectedSize: Int64 // bytes, approximate
        /// SHA-256 hex string of the canonical model file. When set,
        /// `didFinishDownload` rejects any download whose hash doesn't
        /// match (protects against MITM, CDN compromise, or upstream
        /// tampering). Values below are pinned from a known-good local
        /// install on 2026-05-18; if Hugging Face ever republishes a
        /// model under the same filename with a new hash, the download
        /// will reject and the user gets a "Checksum mismatch" status
        /// — at which point we update the constant and ship.
        let expectedSHA256: String?

        init(role: LLMRole, repoID: String, filename: String, expectedSize: Int64, expectedSHA256: String? = nil) {
            self.role = role
            self.repoID = repoID
            self.filename = filename
            self.expectedSize = expectedSize
            self.expectedSHA256 = expectedSHA256
        }

        /// Active downloader registry — mirrors `LLMModelDescriptor.defaults`
        /// so the Model Status download buttons line up with the lineup
        /// chosen for this Mac's tier.
        static var defaults: [HFModelInfo] {
            entries(for: HardwareProfiler.activeTier)
        }

        static func entries(for tier: HardwareTier) -> [HFModelInfo] {
            let embedding = HFModelInfo(
                role: .embedding,
                repoID: "nomic-ai/nomic-embed-text-v1.5-GGUF",
                filename: "nomic-embed-text-v1.5.Q4_K_M.gguf",
                expectedSize: 84_000_000,
                expectedSHA256: "d4e388894e09cf3816e8b0896d81d265b55e7a9fff9ab03fe8bf4ef5e11295ac"
            )
            let vision = HFModelInfo(
                role: .vision,
                repoID: "openbmb/MiniCPM-V-2_6-gguf",
                filename: "ggml-model-Q4_K_M.gguf",
                expectedSize: 5_000_000_000,
                expectedSHA256: "3a4078d53b46f22989adbf998ce5a3fd090b6541f112d7e936eb4204a04100b1"
            )

            switch tier {
            case .low:
                return [
                    HFModelInfo(role: .tagger,
                                repoID: "bartowski/Qwen2.5-3B-Instruct-GGUF",
                                filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
                                expectedSize: 2_000_000_000,
                                expectedSHA256: "9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94"),
                    HFModelInfo(role: .chat,
                                repoID: "bartowski/Qwen2.5-3B-Instruct-GGUF",
                                filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
                                expectedSize: 2_000_000_000,
                                expectedSHA256: "9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94"),
                    embedding,
                ]
            case .standard:
                return [
                    HFModelInfo(role: .tagger,
                                repoID: "bartowski/Qwen2.5-7B-Instruct-GGUF",
                                filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                                expectedSize: 4_700_000_000,
                                expectedSHA256: "65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423"),
                    HFModelInfo(role: .chat,
                                repoID: "bartowski/Qwen2.5-7B-Instruct-GGUF",
                                filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                                expectedSize: 4_700_000_000,
                                expectedSHA256: "65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423"),
                    embedding,
                    vision,
                ]
            case .high, .workstation:
                return [
                    HFModelInfo(role: .tagger,
                                repoID: "bartowski/Qwen2.5-14B-Instruct-GGUF",
                                filename: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
                                expectedSize: 9_000_000_000,
                                expectedSHA256: "e47ad95dad6ff848b431053b375adb5d39321290ea2c638682577dafca87c008"),
                    HFModelInfo(role: .chat,
                                repoID: "bartowski/Qwen2.5-14B-Instruct-GGUF",
                                filename: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
                                expectedSize: 9_000_000_000,
                                expectedSHA256: "e47ad95dad6ff848b431053b375adb5d39321290ea2c638682577dafca87c008"),
                    embedding,
                    vision,
                ]
            }
        }
    }

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        downloadDelegate.downloader = self
    }

    // MARK: - Download Control

    func startDownload(for role: LLMRole) {
        guard let modelInfo = HFModelInfo.defaults.first(where: { $0.role == role }) else { return }
        guard activeTasks[role] == nil else { return }

        // Tagger and chat share a model file (Qwen 14B). If the file is
        // already on disk because the sibling role downloaded it, flip
        // straight to completed without hitting the network.
        let destination = modelsDirectory.appendingPathComponent(modelInfo.filename)
        if FileManager.default.fileExists(atPath: destination.path),
           let size = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber,
           size.int64Value > 1_000_000 {
            downloads[role] = DownloadState(
                status: .completed,
                progress: 1.0,
                bytesWritten: size.int64Value,
                totalBytes: size.int64Value,
                speed: ""
            )
            NotificationCenter.default.post(name: .modelsDidChange, object: nil)
            return
        }

        let url = huggingFaceURL(repo: modelInfo.repoID, filename: modelInfo.filename)
        let task = session.downloadTask(with: url)
        task.taskDescription = role.rawValue
        activeTasks[role] = task
        downloads[role] = DownloadState(
            status: .downloading,
            progress: 0,
            bytesWritten: 0,
            totalBytes: modelInfo.expectedSize,
            speed: "Starting..."
        )
        task.resume()
    }

    func cancelDownload(for role: LLMRole) {
        if let task = activeTasks[role] {
            cancelledTaskIDs.insert(task.taskIdentifier)
            task.cancel()
        }
        activeTasks[role] = nil
        downloads[role] = .idle
    }

    func pauseDownload(for role: LLMRole) {
        activeTasks[role]?.suspend()
        downloads[role]?.status = .paused
    }

    func resumeDownload(for role: LLMRole) {
        activeTasks[role]?.resume()
        downloads[role]?.status = .downloading
    }

    // MARK: - URL Construction

    private func huggingFaceURL(repo: String, filename: String) -> URL {
        // HuggingFace Hub download URL format. Path-escape the filename so
        // names containing spaces or unicode don't produce an invalid URL.
        let escapedFilename = filename
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? filename
        let escapedRepo = repo
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? repo
        let raw = "https://huggingface.co/\(escapedRepo)/resolve/main/\(escapedFilename)"
        // Fall back to a sentinel URL on the impossible-but-defensive failure
        // case; downloader will surface a clear network error rather than crash.
        return URL(string: raw) ?? URL(string: "https://huggingface.co/")!
    }

    // MARK: - Delegate Callbacks

    fileprivate func didUpdateProgress(for role: LLMRole, taskIdentifier: Int, bytesWritten: Int64, totalBytes: Int64, speed: Double) {
        guard isCurrentTask(for: role, taskIdentifier: taskIdentifier) else { return }
        let expectedBytes = normalizedTotalBytes(for: role, reportedTotal: totalBytes)
        let progress = expectedBytes > 0 ? min(max(Double(bytesWritten) / Double(expectedBytes), 0), 1) : 0
        let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
        downloads[role] = DownloadState(
            status: .downloading,
            progress: progress,
            bytesWritten: bytesWritten,
            totalBytes: expectedBytes,
            speed: speedStr
        )
    }

    fileprivate func didFinishDownload(for role: LLMRole, taskIdentifier: Int, tempURL: URL) {
        guard isCurrentTask(for: role, taskIdentifier: taskIdentifier) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        guard let modelInfo = HFModelInfo.defaults.first(where: { $0.role == role }) else { return }
        let destinationURL = modelsDirectory.appendingPathComponent(modelInfo.filename)

        do {
            let downloadedSize = try tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let minimumExpectedSize = Int(Double(modelInfo.expectedSize) * 0.75)
            guard downloadedSize >= minimumExpectedSize else {
                try? FileManager.default.removeItem(at: tempURL)
                downloads[role] = DownloadState(
                    status: .failed,
                    progress: 0,
                    bytesWritten: Int64(downloadedSize),
                    totalBytes: modelInfo.expectedSize,
                    speed: "Downloaded file was too small to be a valid model"
                )
                activeTasks[role] = nil
                return
            }

            // SHA-256 integrity check (when an expected hash is declared
            // for this descriptor). Catches MITM, CDN compromise, and
            // upstream tampering. Skipped silently when no hash is
            // declared — the size check above is the only guard.
            if let expected = modelInfo.expectedSHA256?.lowercased() {
                downloads[role] = DownloadState(
                    status: .verifying,
                    progress: 1.0,
                    bytesWritten: Int64(downloadedSize),
                    totalBytes: modelInfo.expectedSize,
                    speed: "Verifying…"
                )
                let actual = ModelDownloader.sha256Hex(of: tempURL)
                guard actual == expected else {
                    try? FileManager.default.removeItem(at: tempURL)
                    downloads[role] = DownloadState(
                        status: .failed,
                        progress: 0,
                        bytesWritten: Int64(downloadedSize),
                        totalBytes: modelInfo.expectedSize,
                        speed: "Checksum mismatch — file was rejected"
                    )
                    activeTasks[role] = nil
                    return
                }
            }

            // Remove existing file if present
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            downloads[role] = DownloadState(
                status: .completed,
                progress: 1.0,
                bytesWritten: Int64(downloadedSize),
                totalBytes: modelInfo.expectedSize,
                speed: ""
            )
            NotificationCenter.default.post(name: .modelsDidChange, object: nil)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            downloads[role] = DownloadState(
                status: .failed,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 0,
                speed: "Error: \(error.localizedDescription)"
            )
        }
        activeTasks[role] = nil
    }

    fileprivate func didFailDownload(for role: LLMRole, taskIdentifier: Int, error: Error) {
        let wasUserCancelled = cancelledTaskIDs.remove(taskIdentifier) != nil
        let isCurrent = isCurrentTask(for: role, taskIdentifier: taskIdentifier)

        if wasUserCancelled || (isCancellation(error) && !isCurrent) {
            if isCurrent {
                activeTasks[role] = nil
                downloads[role] = .idle
            }
            return
        }

        guard isCurrent else {
            return
        }

        downloads[role] = DownloadState(
            status: .failed,
            progress: downloads[role]?.progress ?? 0,
            bytesWritten: downloads[role]?.bytesWritten ?? 0,
            totalBytes: downloads[role]?.totalBytes ?? 0,
            speed: error.localizedDescription
        )
        activeTasks[role] = nil
    }

    private func normalizedTotalBytes(for role: LLMRole, reportedTotal: Int64) -> Int64 {
        if reportedTotal > 0 { return reportedTotal }
        if let existingTotal = downloads[role]?.totalBytes, existingTotal > 0 {
            return existingTotal
        }
        return HFModelInfo.defaults.first(where: { $0.role == role })?.expectedSize ?? 0
    }

    private func isCurrentTask(for role: LLMRole, taskIdentifier: Int) -> Bool {
        activeTasks[role]?.taskIdentifier == taskIdentifier
    }

    private func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// Streaming SHA-256 of a file URL. Reads the file in 1 MB chunks
    /// so a multi-GB model doesn't have to fit in RAM.
    fileprivate static func sha256Hex(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var downloader: ModelDownloader?
    // URLSession dispatches delegate callbacks from a concurrent operation
    // queue when `delegateQueue: nil`. With multiple roles downloading
    // simultaneously (tagger + chat + embedding tier sweep), didWriteData
    // can fire in parallel for different tasks. The dictionaries below
    // would race; protect them with an NSLock to avoid allocator-level
    // corruption (Swift dictionary CoW is not atomic).
    private let progressLock = NSLock()
    private var lastUpdateTime: [String: Date] = [:]
    private var lastBytesWritten: [String: Int64] = [:]

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let roleStr = downloadTask.taskDescription,
              let role = LLMRole(rawValue: roleStr) else { return }

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let httpError = NSError(
                domain: "ModelDownloader",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): Download failed"]
            )
            Task { @MainActor in
                downloader?.didFailDownload(for: role, taskIdentifier: downloadTask.taskIdentifier, error: httpError)
            }
            return
        }

        // URLSession deletes the temp file after this callback returns,
        // so copy it to a stable location before dispatching to MainActor.
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("athenaeum-dl-\(roleStr)-\(UUID().uuidString).gguf")
        do {
            try FileManager.default.copyItem(at: location, to: stableURL)
        } catch {
            Task { @MainActor in
                downloader?.didFailDownload(for: role, taskIdentifier: downloadTask.taskIdentifier, error: error)
            }
            return
        }

        Task { @MainActor in
            downloader?.didFinishDownload(for: role, taskIdentifier: downloadTask.taskIdentifier, tempURL: stableURL)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let roleStr = downloadTask.taskDescription,
              let role = LLMRole(rawValue: roleStr) else { return }

        // Calculate speed (bytes per second). Read-modify-write under
        // `progressLock` so concurrent delegate callbacks for different
        // roles don't corrupt the dictionaries.
        let now = Date()
        let key = roleStr
        let speed: Double = progressLock.withLock {
            let result: Double
            if let lastTime = lastUpdateTime[key], let lastBytes = lastBytesWritten[key] {
                let elapsed = now.timeIntervalSince(lastTime)
                result = elapsed > 0 ? Double(totalBytesWritten - lastBytes) / elapsed : 0
            } else {
                result = 0
            }
            lastUpdateTime[key] = now
            lastBytesWritten[key] = totalBytesWritten
            return result
        }

        Task { @MainActor in
            downloader?.didUpdateProgress(
                for: role,
                taskIdentifier: downloadTask.taskIdentifier,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite,
                speed: speed
            )
        }
    }

    /// Constrain follow-the-redirect to known Hugging Face hosts so a
    /// hijacked 30x can't redirect us at an attacker-controlled origin
    /// that serves a poisoned model.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              isAllowedRedirectHost(url.host) else {
            completionHandler(nil) // cancels the redirect; task fails
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let roleStr = task.taskDescription,
              let role = LLMRole(rawValue: roleStr) else { return }

        // Check for transport errors
        if let error {
            Task { @MainActor in
                downloader?.didFailDownload(for: role, taskIdentifier: task.taskIdentifier, error: error)
            }
            return
        }

        // Check for HTTP errors (404, 401, etc.)
        if let httpResponse = task.response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let httpError = NSError(
                domain: "ModelDownloader",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): Download failed"]
            )
            Task { @MainActor in
                downloader?.didFailDownload(for: role, taskIdentifier: task.taskIdentifier, error: httpError)
            }
        }
    }
}
