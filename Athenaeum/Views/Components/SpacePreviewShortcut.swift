import SwiftUI
import AppKit

/// Finder-style Space preview shortcut that stays out of text entry controls.
private struct SpacePreviewShortcut: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard shouldTogglePreview(for: event) else { return event }
                    NotificationCenter.default.post(name: .toggleDocumentPreviewPane, object: nil)
                    return nil
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }

    private func shouldTogglePreview(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 49, modifiers.isEmpty, !event.isARepeat else { return false }
        return !Self.focusedResponderAcceptsText
    }

    private static var focusedResponderAcceptsText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField || responder is NSSearchField {
            return true
        }
        return false
    }
}

extension View {
    func spacePreviewShortcut() -> some View {
        modifier(SpacePreviewShortcut())
    }
}
