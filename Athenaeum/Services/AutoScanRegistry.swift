import Foundation
import AppKit

// MARK: - Auto-Scan Folder Registry
//
// Stores the user's list of "watched" folders. Each entry carries a
// security-scoped bookmark so the path survives quits/relaunches even though
// the app is sandboxed. Persistence: a single JSON blob in UserDefaults.

@Observable
final class AutoScanRegistry {
    private(set) var folders: [AutoScanFolder] = []

    private let defaultsKey = "autoScanFolders"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    // MARK: - Public API

    func addFolder(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        // Don't double-add the same path.
        if folders.contains(where: { $0.path == url.standardizedFileURL.path }) { return }

        let entry = AutoScanFolder(
            id: UUID(),
            path: url.standardizedFileURL.path,
            bookmark: bookmark,
            isEnabled: true,
            addedAt: .now
        )
        folders.append(entry)
        save()
        NotificationCenter.default.post(name: .autoScanFoldersDidChange, object: nil)
    }

    func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        save()
        NotificationCenter.default.post(name: .autoScanFoldersDidChange, object: nil)
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].isEnabled = enabled
        save()
        NotificationCenter.default.post(name: .autoScanFoldersDidChange, object: nil)
    }

    /// Resolve a folder's bookmark back to a usable URL. Returns nil if the
    /// folder no longer exists or the sandbox can't grant access. Refreshes
    /// the bookmark transparently if it went stale.
    func resolveURL(for folder: AutoScanFolder) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: folder.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        if stale, let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[idx].bookmark = refreshed
                save()
            }
        }
        return url
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(folders) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([AutoScanFolder].self, from: data) else {
            folders = []
            return
        }
        folders = decoded
    }
}

// MARK: - Folder Model

struct AutoScanFolder: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let path: String
    var bookmark: Data
    var isEnabled: Bool
    let addedAt: Date

    /// Friendly display name — last path component, falling back to the full path.
    var displayName: String {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        return last.isEmpty ? path : last
    }
}

extension Notification.Name {
    // Declared centrally — see AthenaeumApp.swift.
}
