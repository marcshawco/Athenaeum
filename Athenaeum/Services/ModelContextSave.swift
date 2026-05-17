import Foundation
import SwiftData

// MARK: - ModelContext.persist
//
// Wraps `ModelContext.save()` so write failures are surfaced instead of
// dropped on the floor via `try?`. SwiftData saves can fail under disk
// full, an iCloud sync conflict, a uniqueness-constraint violation, or
// a container error — and 30+ call sites in this app were swallowing
// every one of them.
//
// Behavior:
// - On success: returns `true`.
// - On failure: posts `.modelContextSaveFailed` with the error in
//   `userInfo["error"]`, mirrors a one-line message to `NSLog` in
//   DEBUG builds only (NSLog is system-wide on macOS — release builds
//   stay quiet), and returns `false`.
//
// Migration is opt-in: existing `try? modelContext.save()` sites still
// compile and silently drop errors as before. Higher-traffic sites
// (chat conversation persistence, batch deletes, document edits) are
// migrated to `modelContext.persist()` so the user sees a banner when
// a save fails. The remaining sites can be migrated incrementally
// without breaking anything.

extension Notification.Name {
    /// Posted when `ModelContext.persist()` catches a save error.
    /// `userInfo["error"]` carries the underlying `Error`.
    /// `userInfo["context"]` (optional) carries a caller-supplied
    /// description like "chat-save" for diagnostics.
    static let modelContextSaveFailed = Notification.Name("modelContextSaveFailed")
}

extension ModelContext {
    /// Save the context, returning `true` on success. On failure posts
    /// `.modelContextSaveFailed` (so a banner can surface it) and
    /// returns `false`. Replaces `try? modelContext.save()` at the
    /// callers that care about durability.
    ///
    /// - Parameter context: optional short tag for diagnostics
    ///   (e.g. "chat-save", "batch-delete"). Goes into the
    ///   notification's `userInfo` so a banner can disambiguate.
    @discardableResult
    func persist(context tag: String? = nil) -> Bool {
        do {
            try save()
            return true
        } catch {
            var userInfo: [String: Any] = ["error": error]
            if let tag { userInfo["context"] = tag }
            NotificationCenter.default.post(
                name: .modelContextSaveFailed,
                object: nil,
                userInfo: userInfo
            )
            #if DEBUG
            NSLog("[ATHENS] ModelContext.save failed%@: %@",
                  tag.map { " (\($0))" } ?? "",
                  String(describing: error))
            #endif
            return false
        }
    }
}
