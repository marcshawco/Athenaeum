import AppKit
import Foundation

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Last-window-close hook: on macOS, closing the window does NOT
        // quit the app — without this, loaded models would sit on
        // gigabytes of unified memory with no UI open. When the last
        // regular window closes, release all model memory ("pause").
        // The models reload transparently on the next request after the
        // user reopens the window.
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Let the closing window leave the window list first.
                try? await Task.sleep(for: .milliseconds(250))
                let hasVisibleWindow = NSApp.windows.contains {
                    $0.isVisible && $0.canBecomeKey
                }
                if !hasVisibleWindow {
                    LocalLLMLifecycleCoordinator.shared.releaseModelMemoryForBackground()
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Child processes (whisper-cli) are not killed by macOS when the
        // parent quits — terminate them explicitly, models or not.
        TranscriptionService.terminateActiveProcesses()

        guard LocalLLMLifecycleCoordinator.shared.hasActiveService else {
            return .terminateNow
        }

        LocalLLMLifecycleCoordinator.shared.shutdownBeforeTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
final class LocalLLMLifecycleCoordinator {
    static let shared = LocalLLMLifecycleCoordinator()

    private weak var llmService: LocalLLMService?
    private var isTerminating = false

    var hasActiveService: Bool {
        llmService != nil
    }

    private init() {}

    func register(_ service: LocalLLMService) {
        guard !isTerminating else { return }
        llmService = service
    }

    /// "Pause" — free all model memory while keeping the app (and its
    /// services) alive. Used when the last window closes. Unlike
    /// `shutdownBeforeTermination` this is fully reversible: the next
    /// inference request reloads whatever it needs.
    func releaseModelMemoryForBackground() {
        guard !isTerminating, let service = llmService else { return }
        Task {
            await service.releaseAllModelMemory()
        }
    }

    func shutdownBeforeTermination(completion: @escaping () -> Void) {
        guard !isTerminating else {
            completion()
            return
        }
        isTerminating = true

        let service = llmService
        Task {
            await service?.shutdownForAppTermination()
            llmService = nil
            completion()
        }
    }
}
