import Foundation
import CoreServices

/// Watches the vault folder while Athenaeum is open and asks the app to rescan
/// after Finder writes settle.
final class DocumentVaultMonitor {
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (() -> Void)?
    private var securityScopedURL: URL?
    private var isAccessingSecurityScope = false

    private let eventQueue = DispatchQueue(label: "app.athenaeum.document-vault-monitor")
    private let latency: CFTimeInterval = 1.0
    private let debounceDelay: TimeInterval = 1.25

    private(set) var isWatching = false
    private(set) var lastError: String?

    func start(watching url: URL, onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        securityScopedURL = url
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            documentVaultEventCallback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            releaseSecurityScope()
            lastError = "Could not create document vault watcher."
            return
        }

        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            releaseSecurityScope()
            lastError = "Could not start document vault watcher."
            return
        }

        self.stream = stream
        isWatching = true
        lastError = nil
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        isWatching = false
        releaseSecurityScope()
    }

    fileprivate func scheduleRescan() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWorkItem = workItem
        eventQueue.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    deinit {
        stop()
    }

    private func releaseSecurityScope() {
        if isAccessingSecurityScope {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }
        securityScopedURL = nil
    }
}

private let documentVaultEventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    let monitor = Unmanaged<DocumentVaultMonitor>.fromOpaque(info).takeUnretainedValue()
    monitor.scheduleRescan()
}
