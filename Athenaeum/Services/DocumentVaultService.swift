import Foundation
import UniformTypeIdentifiers
import AppKit

/// Owns the user-visible local document vault.
///
/// Athenaeum keeps SwiftData records for search, tags, chat, and previews, but
/// original files also live in a normal Finder folder so users can add documents
/// directly without opening an import sheet.
final class DocumentVaultService {
    static let shared = DocumentVaultService()

    static let vaultDidChangeNotification = Notification.Name("documentVaultDidChange")

    private let fileManager = FileManager.default
    private let bookmarkKey = "documentVaultBookmark"
    private let pathKey = "documentVaultPath"
    private let minimumImportAge: TimeInterval = 1.0

    private init() {}

    var vaultURL: URL {
        if let bookmarkURL = resolveBookmarkedVaultURL(),
           isWritable(bookmarkURL) {
            return bookmarkURL
        }

        if let path = UserDefaults.standard.string(forKey: pathKey),
           !path.isEmpty,
           isWritable(URL(fileURLWithPath: path, isDirectory: true)) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        // No persisted location works — clear stale defaults so we don't keep
        // re-trying the dead path on every launch, then fall through to the
        // default location below.
        if UserDefaults.standard.object(forKey: bookmarkKey) != nil ||
           UserDefaults.standard.object(forKey: pathKey) != nil {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            UserDefaults.standard.removeObject(forKey: pathKey)
        }

        return defaultVaultURL
    }

    /// The vault location we'd use if no user override is set. Lives under
    /// ~/Documents/Athenaeum Library by default (visible in Finder), with a
    /// sandbox-safe fallback under Application Support.
    var defaultVaultURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let preferred = documents?.appendingPathComponent("Athenaeum Library", isDirectory: true)
        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Athenaeum/Document Vault", isDirectory: true)
        return preferred ?? fallback
    }

    /// Returns true when the given directory is writeable from the current
    /// sandbox. Cheap probe — creates and removes a unique temp file rather
    /// than relying on `FileManager.isWritableFile`, which lies when the
    /// path used to be readable but its security scope has expired.
    private func isWritable(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let probe = url.appendingPathComponent(".athenaeum-write-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try? fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    /// Drop any stored vault override (bookmark + path) and revert to the
    /// default location under ~/Documents. Surfaced as Settings ▸ Storage ▸
    /// "Reset vault to default" so users can recover from the stale-bookmark
    /// error ("Failed to scan document vault: You don't have permission…").
    func resetToDefaultVault() throws {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
        let url = defaultVaultURL
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.path, forKey: pathKey)
        NotificationCenter.default.post(name: Self.vaultDidChangeNotification, object: nil)
    }

    @discardableResult
    func prepareVault() throws -> URL {
        let url = vaultURL
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.path, forKey: pathKey)
        return url
    }

    func setVaultURL(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: pathKey)
        NotificationCenter.default.post(name: Self.vaultDidChangeNotification, object: nil)
    }

    func revealVault() {
        if let url = try? prepareVault() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func withVaultAccess<T>(_ work: (URL) throws -> T) rethrows -> T {
        let url = vaultURL
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try work(url)
    }

    func storeExternalFile(_ sourceURL: URL) throws -> URL {
        try prepareVault()

        let accessingSource = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessingSource { sourceURL.stopAccessingSecurityScopedResource() } }

        return try withVaultAccess { vault in
            let destination = uniqueDestinationURL(for: sourceURL.lastPathComponent, in: vault)
            if sourceURL.standardizedFileURL.path == destination.standardizedFileURL.path {
                return destination
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }

    func storeData(_ data: Data, preferredFilename: String) throws -> URL {
        try prepareVault()

        return try withVaultAccess { vault in
            let destination = uniqueDestinationURL(for: preferredFilename, in: vault)
            try data.write(to: destination, options: .atomic)
            return destination
        }
    }

    func scanForDocuments() throws -> [URL] {
        try prepareVault()

        return withVaultAccess { vault in
            guard let enumerator = fileManager.enumerator(
                at: vault,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .typeIdentifierKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            var urls: [URL] = []
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey])
                guard values?.isRegularFile == true, values?.isHidden != true else { continue }
                guard isSupportedDocument(url) else { continue }
                guard isReadyForImport(values: values, url: url) else { continue }
                urls.append(url)
            }
            return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }

    func isInVault(_ url: URL) -> Bool {
        // Resolve symlinks on BOTH sides before comparing. A bare path
        // comparison lets an attacker drop a symlink into the vault whose
        // target lives outside the vault — later "Delete" inside the app
        // would silently trash whatever the symlink points at, since the
        // sandbox grants vault-wide read-write.
        let vaultPath = vaultURL.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return filePath == vaultPath || filePath.hasPrefix(vaultPath + "/")
    }

    private func resolveBookmarkedVaultURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

        if stale, let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }

        UserDefaults.standard.set(url.path, forKey: pathKey)
        return url
    }

    private func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent.nilIfBlank ?? "Document"
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(counter)"
            candidate = ext.isEmpty
                ? directory.appendingPathComponent(numbered)
                : directory.appendingPathComponent(numbered).appendingPathExtension(ext)
            counter += 1
        }

        return candidate
    }

    private func isSupportedDocument(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let ignoredExtensions: Set<String> = ["download", "crdownload", "part", "tmp", "temp"]
        if ignoredExtensions.contains(ext) { return false }

        let filename = url.lastPathComponent
        if filename.hasPrefix(".") || filename.hasSuffix(".icloud") { return false }

        let allowedExtensions: Set<String> = [
            "pdf", "txt", "text", "rtf", "rtfd", "doc", "docx", "odt", "pages",
            "csv", "tsv", "json", "xml", "md", "markdown", "html", "htm",
            "png", "jpg", "jpeg", "tif", "tiff", "heic", "webp", "gif",
            "xls", "xlsx", "numbers", "ppt", "pptx", "key",
            "eml", "msg", "ics",
            "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac",
            "mp4", "m4v", "mov", "avi", "mkv", "webm"
        ]
        if allowedExtensions.contains(ext) { return true }

        let type = UTType(filenameExtension: ext)
        return type?.conforms(to: .pdf) == true ||
            type?.conforms(to: .text) == true ||
            type?.conforms(to: .image) == true ||
            type?.conforms(to: .content) == true
    }

    private func isReadyForImport(values: URLResourceValues?, url: URL) -> Bool {
        guard let values else { return false }
        if (values.fileSize ?? 0) <= 0 { return false }

        if let modified = values.contentModificationDate,
           Date().timeIntervalSince(modified) < minimumImportAge {
            return false
        }

        return fileManager.isReadableFile(atPath: url.path)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
