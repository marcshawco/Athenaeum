import AppKit
import Foundation

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
