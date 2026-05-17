import Foundation

@main
struct VaultSmokeTest {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("athenaeum-vault-smoke-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)

        try fileManager.createDirectory(at: vault, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        UserDefaults.standard.removeObject(forKey: "documentVaultBookmark")
        UserDefaults.standard.set(vault.path, forKey: "documentVaultPath")

        let preparedVault = try DocumentVaultService.shared.prepareVault()
        try assert(preparedVault.standardizedFileURL == vault.standardizedFileURL, "Vault path was not respected")

        let ready = vault.appendingPathComponent("ready-contract.pdf")
        try Data("ready".utf8).write(to: ready)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -5)], ofItemAtPath: ready.path)

        let ignoredDownload = vault.appendingPathComponent("partial.pdf.download")
        try Data("partial".utf8).write(to: ignoredDownload)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -5)], ofItemAtPath: ignoredDownload.path)

        let zeroByte = vault.appendingPathComponent("empty.pdf")
        fileManager.createFile(atPath: zeroByte.path, contents: nil)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -5)], ofItemAtPath: zeroByte.path)

        let tooFresh = vault.appendingPathComponent("fresh.pdf")
        try Data("fresh".utf8).write(to: tooFresh)

        let scanned = try DocumentVaultService.shared.scanForDocuments().map(\.lastPathComponent)
        try assert(scanned == ["ready-contract.pdf"], "Unexpected scan result: \(scanned)")

        let source = external.appendingPathComponent("invoice.pdf")
        try Data("invoice".utf8).write(to: source)
        let stored = try DocumentVaultService.shared.storeExternalFile(source)
        try assert(stored.deletingLastPathComponent().standardizedFileURL == vault.standardizedFileURL, "External file was not copied into vault")
        try assert(fileManager.fileExists(atPath: stored.path), "Stored file does not exist")

        let storedAgain = try DocumentVaultService.shared.storeExternalFile(source)
        try assert(storedAgain.lastPathComponent != stored.lastPathComponent, "Duplicate vault copy did not get a unique name")

        let restored = try DocumentVaultService.shared.storeData(Data("restored".utf8), preferredFilename: "restored.txt")
        try assert(restored.deletingLastPathComponent().standardizedFileURL == vault.standardizedFileURL, "Stored data was not written into vault")
        let restoredText = String(data: try Data(contentsOf: restored), encoding: .utf8)
        try assert(restoredText == "restored", "Stored data contents were not preserved")

        print("Vault smoke test passed")
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SmokeTestError(message)
        }
    }
}

private struct SmokeTestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
