import AppKit
import CommonCrypto
import Foundation
import Security
import SwiftData

// MARK: - Migration Backup

struct BackupProgress: Equatable {
    var message: String
    var completedBytes: Int64
    var totalBytes: Int64

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

struct BackupSummary {
    let destination: URL
    let documentCount: Int
    let originalFileCount: Int
    let vectorStoreCount: Int
    let byteCount: Int64
}

enum BackupError: LocalizedError {
    case emptyPassphrase
    case passphraseTooShort
    case invalidDestination
    case encryptionFailed(String)
    case randomBytesFailed
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyPassphrase:
            "Enter a backup passphrase."
        case .passphraseTooShort:
            "Use at least 8 characters for the backup passphrase."
        case .invalidDestination:
            "Choose a valid backup destination."
        case .encryptionFailed(let message):
            "Encryption failed: \(message)"
        case .randomBytesFailed:
            "Could not create secure random bytes for the backup."
        case .archiveFailed(let message):
            "Backup failed: \(message)"
        }
    }
}

@MainActor
final class BackupService {
    static let shared = BackupService()

    private init() {}

    func createBackup(
        to destination: URL,
        passphrase: String,
        context: ModelContext,
        progress: @escaping @MainActor (BackupProgress) -> Void
    ) async throws -> BackupSummary {
        let cleanPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPassphrase.isEmpty else { throw BackupError.emptyPassphrase }
        guard cleanPassphrase.count >= 8 else { throw BackupError.passphraseTooShort }
        guard destination.pathExtension.lowercased() == "athensbackup" else {
            throw BackupError.invalidDestination
        }

        let plan = try makePlan(context: context)
        progress(BackupProgress(message: "Preparing archive...", completedBytes: 0, totalBytes: plan.totalBytes))

        return try await Task.detached(priority: .userInitiated) {
            let writer = EncryptedArchiveWriter()
            try await writer.write(
                plan: plan,
                destination: destination,
                passphrase: cleanPassphrase
            ) { update in
                await MainActor.run { progress(update) }
            }
            return BackupSummary(
                destination: destination,
                documentCount: plan.documentCount,
                originalFileCount: plan.originalFileCount,
                vectorStoreCount: plan.vectorStoreCount,
                byteCount: plan.totalBytes
            )
        }.value
    }

    private func makePlan(context: ModelContext) throws -> BackupPlan {
        let documents = try context.fetch(FetchDescriptor<Document>())
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let tags = try context.fetch(FetchDescriptor<Tag>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let folders = try context.fetch(FetchDescriptor<Folder>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let entries = try context.fetch(FetchDescriptor<KnowledgeEntry>())
            .sorted { $0.canonicalName.localizedStandardCompare($1.canonicalName) == .orderedAscending }
        let chats = try context.fetch(FetchDescriptor<ChatConversation>())
            .sorted { $0.modifiedAt > $1.modifiedAt }

        let vaultURL = DocumentVaultService.shared.vaultURL
        let appSupportURL = Self.appSupportURL
        let vectorStoreURLs = Self.vectorStoreURLs(in: appSupportURL)
        let vaultFiles = Self.vaultFileURLs(in: vaultURL)
        let recoveredOriginals = documents.compactMap(Self.recoveredOriginalRecord(for:))

        let snapshot = SwiftDataBackupSnapshot(
            exportedAt: Date(),
            documents: documents.map { SwiftDataDocumentSnapshot(document: $0, vaultURL: vaultURL) },
            tags: tags.map(SwiftDataTagSnapshot.init(tag:)),
            folders: folders.map(SwiftDataFolderSnapshot.init(folder:)),
            knowledgeEntries: entries.map(SwiftDataKnowledgeEntrySnapshot.init(entry:)),
            chatConversations: chats.map(SwiftDataChatSnapshot.init(chat:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let snapshotData = try encoder.encode(snapshot)
        let manifest = BackupManifest(
            formatVersion: 1,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            createdAt: Date(),
            sourceHostName: Host.current().localizedName ?? Host.current().name ?? "Unknown Mac",
            vaultPath: vaultURL.path,
            appSupportPath: appSupportURL.path,
            documentCount: documents.count,
            tagCount: tags.count,
            folderCount: folders.count,
            knowledgeEntryCount: entries.count,
            chatConversationCount: chats.count,
            originalFileCount: vaultFiles.count + recoveredOriginals.count,
            vectorStoreCount: vectorStoreURLs.count
        )
        let manifestData = try encoder.encode(manifest)

        var records: [BackupRecord] = [
            .data(
                data: manifestData,
                archivePath: "manifest.json",
                kind: .manifest,
                modifiedAt: Date()
            ),
            .data(
                data: snapshotData,
                archivePath: "SwiftData/swiftdata-export.json",
                kind: .swiftDataJSON,
                modifiedAt: Date()
            )
        ]

        records.append(contentsOf: vaultFiles.map {
            BackupRecord.file(
                url: $0.url,
                archivePath: "Originals/Vault/\($0.relativePath)",
                kind: .originalDocument,
                byteCount: $0.byteCount,
                modifiedAt: $0.modifiedAt
            )
        })
        records.append(contentsOf: recoveredOriginals)
        records.append(contentsOf: vectorStoreURLs.map {
            BackupRecord.file(
                url: $0.url,
                archivePath: "VectorStores/\($0.url.lastPathComponent)",
                kind: .vectorStore,
                byteCount: $0.byteCount,
                modifiedAt: $0.modifiedAt
            )
        })

        return BackupPlan(
            records: records,
            vaultURL: vaultURL,
            totalBytes: records.reduce(0) { $0 + $1.byteCount },
            documentCount: documents.count,
            originalFileCount: vaultFiles.count + recoveredOriginals.count,
            vectorStoreCount: vectorStoreURLs.count
        )
    }
}

// MARK: - Backup Plan

private nonisolated struct BackupPlan: Sendable {
    let records: [BackupRecord]
    let vaultURL: URL
    let totalBytes: Int64
    let documentCount: Int
    let originalFileCount: Int
    let vectorStoreCount: Int
}

private nonisolated enum BackupRecord: Sendable {
    case data(data: Data, archivePath: String, kind: BackupRecordKind, modifiedAt: Date?)
    case file(url: URL, archivePath: String, kind: BackupRecordKind, byteCount: Int64, modifiedAt: Date?)

    var archivePath: String {
        switch self {
        case .data(_, let archivePath, _, _), .file(_, let archivePath, _, _, _):
            archivePath
        }
    }

    var kind: BackupRecordKind {
        switch self {
        case .data(_, _, let kind, _), .file(_, _, let kind, _, _):
            kind
        }
    }

    var byteCount: Int64 {
        switch self {
        case .data(let data, _, _, _):
            Int64(data.count)
        case .file(_, _, _, let byteCount, _):
            byteCount
        }
    }

    var modifiedAt: Date? {
        switch self {
        case .data(_, _, _, let modifiedAt), .file(_, _, _, _, let modifiedAt):
            modifiedAt
        }
    }
}

private nonisolated enum BackupRecordKind: String, Codable, Sendable {
    case manifest
    case swiftDataJSON
    case originalDocument
    case recoveredOriginal
    case vectorStore
}

private nonisolated struct BackupEntryHeader: Codable {
    let path: String
    let kind: BackupRecordKind
    let byteCount: Int64
    let modifiedAt: Date?
}

private nonisolated struct BackupManifest: Codable {
    let formatVersion: Int
    let appVersion: String
    let buildNumber: String
    let createdAt: Date
    let sourceHostName: String
    let vaultPath: String
    let appSupportPath: String
    let documentCount: Int
    let tagCount: Int
    let folderCount: Int
    let knowledgeEntryCount: Int
    let chatConversationCount: Int
    let originalFileCount: Int
    let vectorStoreCount: Int
}

// MARK: - SwiftData Snapshot

private nonisolated struct SwiftDataBackupSnapshot: Codable {
    let exportedAt: Date
    let documents: [SwiftDataDocumentSnapshot]
    let tags: [SwiftDataTagSnapshot]
    let folders: [SwiftDataFolderSnapshot]
    let knowledgeEntries: [SwiftDataKnowledgeEntrySnapshot]
    let chatConversations: [SwiftDataChatSnapshot]
}

private nonisolated struct SwiftDataDocumentSnapshot: Codable {
    let id: UUID
    let title: String
    let originalFilename: String
    let fileType: String
    let fileSize: Int64
    let storagePath: String?
    let vaultRelativePath: String?
    let extractedText: String?
    let summary: String?
    let tagNames: [String]
    let folderIDs: [UUID]
    let correspondent: String?
    let documentDate: Date?
    let importedAt: Date
    let modifiedAt: Date
    let documentTypeSlug: String?
    let categorySlug: String?
    let processingStatus: String
    let processingError: String?
    let searchableText: String?

    init(document: Document, vaultURL: URL) {
        self.id = document.id
        self.title = document.title
        self.originalFilename = document.originalFilename
        self.fileType = document.fileType
        self.fileSize = document.fileSize
        self.storagePath = document.storagePath
        self.vaultRelativePath = document.storedFileURL.flatMap {
            BackupService.relativePath(for: $0, under: vaultURL)
        }
        self.extractedText = document.extractedText
        self.summary = document.summary
        self.tagNames = (document.tags ?? []).map(\.name).sorted()
        self.folderIDs = (document.folders ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
        self.correspondent = document.correspondent
        self.documentDate = document.documentDate
        self.importedAt = document.importedAt
        self.modifiedAt = document.modifiedAt
        self.documentTypeSlug = document.documentTypeSlug
        self.categorySlug = document.categorySlug
        self.processingStatus = document.processingStatus.rawValue
        self.processingError = document.processingError
        self.searchableText = document.searchableText
    }
}

private nonisolated struct SwiftDataTagSnapshot: Codable {
    let name: String
    let colorHex: String
    let createdAt: Date
    let documentIDs: [UUID]

    init(tag: Tag) {
        self.name = tag.name
        self.colorHex = tag.colorHex
        self.createdAt = tag.createdAt
        self.documentIDs = (tag.documents ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
    }
}

private nonisolated struct SwiftDataFolderSnapshot: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let createdAt: Date
    let modifiedAt: Date
    let documentIDs: [UUID]

    init(folder: Folder) {
        self.id = folder.id
        self.name = folder.name
        self.colorHex = folder.colorHex
        self.createdAt = folder.createdAt
        self.modifiedAt = folder.modifiedAt
        self.documentIDs = (folder.documents ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
    }
}

private nonisolated struct SwiftDataKnowledgeEntrySnapshot: Codable {
    let id: UUID
    let canonicalName: String
    let aliases: [String]
    let notes: String?
    let category: String?
    let isSelf: Bool
    let createdAt: Date
    let modifiedAt: Date

    init(entry: KnowledgeEntry) {
        self.id = entry.id
        self.canonicalName = entry.canonicalName
        self.aliases = entry.aliases
        self.notes = entry.notes
        self.category = entry.category
        self.isSelf = entry.isSelf
        self.createdAt = entry.createdAt
        self.modifiedAt = entry.modifiedAt
    }
}

private nonisolated struct SwiftDataChatSnapshot: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let modifiedAt: Date
    let messagesJSON: String

    init(chat: ChatConversation) {
        self.id = chat.id
        self.title = chat.title
        self.createdAt = chat.createdAt
        self.modifiedAt = chat.modifiedAt
        self.messagesJSON = chat.messagesJSON
    }
}

// MARK: - Archive Writer

private nonisolated final class EncryptedArchiveWriter: @unchecked Sendable {
    private let chunkSize = 1024 * 1024
    private let iterations: UInt32 = 150_000

    func write(
        plan: BackupPlan,
        destination: URL,
        passphrase: String,
        progress: (BackupProgress) async -> Void
    ) async throws {
        let destinationAccess = destination.deletingLastPathComponent().startAccessingSecurityScopedResource()
        defer { if destinationAccess { destination.deletingLastPathComponent().stopAccessingSecurityScopedResource() } }

        let vaultAccess = plan.vaultURL.startAccessingSecurityScopedResource()
        defer { if vaultAccess { plan.vaultURL.stopAccessingSecurityScopedResource() } }

        let tempURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: tempURL) else {
            throw BackupError.invalidDestination
        }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            var completedBytes: Int64 = 0
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]

            let encryptor = try StreamingArchiveEncryptor(
                output: output,
                passphrase: passphrase,
                iterations: iterations
            )

            try encryptor.writePlain(Data("ATHENSARCHIVE1\n".utf8))

            for record in plan.records {
                await progress(BackupProgress(
                    message: "Adding \(record.archivePath)",
                    completedBytes: completedBytes,
                    totalBytes: plan.totalBytes
                ))

                let header = BackupEntryHeader(
                    path: record.archivePath,
                    kind: record.kind,
                    byteCount: record.byteCount,
                    modifiedAt: record.modifiedAt
                )
                let headerData = try encoder.encode(header)
                try encryptor.writePlain(Data(bigEndian: UInt64(headerData.count)))
                try encryptor.writePlain(headerData)

                switch record {
                case .data(let data, _, _, _):
                    try encryptor.writePlain(data)
                    completedBytes += Int64(data.count)
                case .file(let url, _, _, let byteCount, _):
                    try writeFile(url, byteCount: byteCount, encryptor: encryptor) { written in
                        completedBytes += written
                    }
                }
            }

            try encryptor.writePlain(Data(bigEndian: UInt64(0)))
            try encryptor.finalize()
            try output.close()

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            await progress(BackupProgress(
                message: "Backup complete",
                completedBytes: plan.totalBytes,
                totalBytes: plan.totalBytes
            ))
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private func writeFile(
        _ url: URL,
        byteCount: Int64,
        encryptor: StreamingArchiveEncryptor,
        didWrite: (Int64) -> Void
    ) throws {
        guard let input = try? FileHandle(forReadingFrom: url) else {
            throw BackupError.archiveFailed("Could not read \(url.lastPathComponent).")
        }
        defer { try? input.close() }

        var remaining = byteCount
        while remaining > 0 {
            let readSize = min(chunkSize, Int(remaining))
            let data = try input.read(upToCount: readSize) ?? Data()
            guard !data.isEmpty else { break }
            try encryptor.writePlain(data)
            let count = Int64(data.count)
            didWrite(count)
            remaining -= count
        }
    }
}

private nonisolated final class StreamingArchiveEncryptor {
    private let output: FileHandle
    private var cryptor: CCCryptorRef?
    private var hmac = CCHmacContext()
    private var finalized = false

    init(output: FileHandle, passphrase: String, iterations: UInt32) throws {
        self.output = output

        let salt = try Self.randomData(count: 16)
        let iv = try Self.randomData(count: kCCBlockSizeAES128)
        let keyMaterial = try Self.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let encryptionKey = keyMaterial.prefix(32)
        let macKey = keyMaterial.suffix(32)

        var header = Data("ATHENSBACKUP1".utf8)
        header.append(1)
        header.append(Data(bigEndian: iterations))
        header.append(salt)
        header.append(iv)
        try output.write(contentsOf: header)

        macKey.withUnsafeBytes { keyPointer in
            CCHmacInit(&hmac, CCHmacAlgorithm(kCCHmacAlgSHA256), keyPointer.baseAddress, macKey.count)
        }
        header.withUnsafeBytes { CCHmacUpdate(&hmac, $0.baseAddress, header.count) }

        let status = encryptionKey.withUnsafeBytes { keyPointer in
            iv.withUnsafeBytes { ivPointer in
                CCCryptorCreate(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyPointer.baseAddress,
                    encryptionKey.count,
                    ivPointer.baseAddress,
                    &cryptor
                )
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.encryptionFailed(Self.statusMessage(status))
        }
    }

    deinit {
        if let cryptor {
            CCCryptorRelease(cryptor)
        }
    }

    func writePlain(_ data: Data) throws {
        guard !finalized else { throw BackupError.archiveFailed("Archive already finalized.") }
        guard !data.isEmpty else { return }
        guard let cryptor else { throw BackupError.encryptionFailed("Missing encryptor.") }

        var outputData = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = outputData.count
        var outputLength = 0
        let status = data.withUnsafeBytes { dataPointer in
            outputData.withUnsafeMutableBytes { outputPointer in
                CCCryptorUpdate(
                    cryptor,
                    dataPointer.baseAddress,
                    data.count,
                    outputPointer.baseAddress,
                    outputCapacity,
                    &outputLength
                )
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.encryptionFailed(Self.statusMessage(status))
        }

        if outputLength > 0 {
            outputData.removeSubrange(outputLength..<outputData.count)
            try writeCipher(outputData)
        }
    }

    func finalize() throws {
        guard !finalized else { return }
        guard let cryptor else { throw BackupError.encryptionFailed("Missing encryptor.") }

        var finalData = Data(count: kCCBlockSizeAES128)
        let finalCapacity = finalData.count
        var finalLength = 0
        let status = finalData.withUnsafeMutableBytes { outputPointer in
            CCCryptorFinal(
                cryptor,
                outputPointer.baseAddress,
                finalCapacity,
                &finalLength
            )
        }
        guard status == kCCSuccess else {
            throw BackupError.encryptionFailed(Self.statusMessage(status))
        }
        if finalLength > 0 {
            finalData.removeSubrange(finalLength..<finalData.count)
            try writeCipher(finalData)
        }

        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { CCHmacFinal(&hmac, $0.baseAddress) }
        try output.write(contentsOf: digest)
        finalized = true
    }

    private func writeCipher(_ data: Data) throws {
        data.withUnsafeBytes { CCHmacUpdate(&hmac, $0.baseAddress, data.count) }
        try output.write(contentsOf: data)
    }

    private static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw BackupError.randomBytesFailed }
        return data
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> Data {
        let passphraseData = Data(passphrase.utf8)
        var key = Data(count: 64)
        let keyCount = key.count
        let status = passphraseData.withUnsafeBytes { passphrasePointer in
            salt.withUnsafeBytes { saltPointer in
                key.withUnsafeMutableBytes { keyPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphrasePointer.bindMemory(to: Int8.self).baseAddress,
                        passphraseData.count,
                        saltPointer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        keyPointer.bindMemory(to: UInt8.self).baseAddress,
                        keyCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.encryptionFailed(statusMessage(status))
        }
        return key
    }

    private static func statusMessage(_ status: CCCryptorStatus) -> String {
        "CommonCrypto status \(status)"
    }
}

// MARK: - Filesystem Helpers

private extension BackupService {
    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Athenaeum", isDirectory: true)
    }

    static func vaultFileURLs(in vaultURL: URL) -> [(url: URL, relativePath: String, byteCount: Int64, modifiedAt: Date?)] {
        let access = vaultURL.startAccessingSecurityScopedResource()
        defer { if access { vaultURL.stopAccessingSecurityScopedResource() } }

        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [(URL, String, Int64, Date?)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  values?.isHidden != true,
                  values?.isSymbolicLink != true,
                  let relativePath = relativePath(for: url, under: vaultURL) else {
                continue
            }
            files.append((url, relativePath, Int64(values?.fileSize ?? 0), values?.contentModificationDate))
        }
        return files.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    static func vectorStoreURLs(in appSupportURL: URL) -> [(url: URL, byteCount: Int64, modifiedAt: Date?)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("vector_store"),
                  url.pathExtension.lowercased() == "json" else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { return nil }
            return (url, Int64(values?.fileSize ?? 0), values?.contentModificationDate)
        }
        .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    static func recoveredOriginalRecord(for document: Document) -> BackupRecord? {
        guard document.storedFileURL == nil ||
              document.storedFileURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true,
              let data = document.fileData else {
            return nil
        }

        let safeName = sanitizedPathComponent(document.originalFilename).nilIfBlank ?? "Original"
        return .data(
            data: data,
            archivePath: "Originals/Recovered/\(document.id.uuidString)/\(safeName)",
            kind: .recoveredOriginal,
            modifiedAt: document.modifiedAt
        )
    }

    nonisolated static func relativePath(for url: URL, under rootURL: URL) -> String? {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { return nil }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative
            .split(separator: "/")
            .map { sanitizedPathComponent(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
            .nilIfBlank
    }

    nonisolated static func sanitizedPathComponent(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private nonisolated extension Data {
    init(bigEndian value: UInt64) {
        var bigEndianValue = value.bigEndian
        self.init(bytes: &bigEndianValue, count: MemoryLayout<UInt64>.size)
    }

    init(bigEndian value: UInt32) {
        var bigEndianValue = value.bigEndian
        self.init(bytes: &bigEndianValue, count: MemoryLayout<UInt32>.size)
    }
}

private nonisolated extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
