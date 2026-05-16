import Foundation

// MARK: - Model Downloader
// Downloads GGUF models from HuggingFace Hub with progress tracking and resume support.

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

        static let defaults: [HFModelInfo] = [
            HFModelInfo(
                role: .tagger,
                repoID: "bartowski/Qwen2.5-7B-Instruct-GGUF",
                filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                expectedSize: 4_700_000_000
            ),
            HFModelInfo(
                role: .chat,
                repoID: "bartowski/Mistral-7B-Instruct-v0.3-GGUF",
                filename: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
                expectedSize: 4_400_000_000
            ),
            HFModelInfo(
                role: .vision,
                repoID: "openbmb/MiniCPM-V-2_6-gguf",
                filename: "ggml-model-Q4_K_M.gguf",
                expectedSize: 5_000_000_000
            ),
        ]
    }

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        downloadDelegate.downloader = self
    }

    // MARK: - Download Control

    func startDownload(for role: LLMRole) {
        guard let modelInfo = HFModelInfo.defaults.first(where: { $0.role == role }) else { return }
        guard activeTasks[role] == nil else { return }

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
        // HuggingFace Hub download URL format
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")!
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
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var downloader: ModelDownloader?
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

        // Calculate speed (bytes per second)
        let now = Date()
        let key = roleStr
        let speed: Double
        if let lastTime = lastUpdateTime[key], let lastBytes = lastBytesWritten[key] {
            let elapsed = now.timeIntervalSince(lastTime)
            speed = elapsed > 0 ? Double(totalBytesWritten - lastBytes) / elapsed : 0
        } else {
            speed = 0
        }
        lastUpdateTime[key] = now
        lastBytesWritten[key] = totalBytesWritten

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
