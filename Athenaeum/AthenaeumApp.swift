import SwiftUI
import SwiftData

@main
struct AthenaeumApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
                .tint(Japandi.Colors.accentFallback)
        }
        .modelContainer(for: [Document.self, Tag.self])
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Documents...") {
                    NotificationCenter.default.post(name: .importDocuments, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Scan Folder for Import...") {
                    NotificationCenter.default.post(name: .scanFolderForImport, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Scan Document Vault") {
                    NotificationCenter.default.post(name: .scanDocumentVault, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Reveal Document Vault") {
                    DocumentVaultService.shared.revealVault()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Document") {
                Button("Toggle Preview Pane") {
                    NotificationCenter.default.post(name: .toggleDocumentPreviewPane, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let importDocuments    = Notification.Name("importDocuments")
    static let openSettings       = Notification.Name("openSettings")
    static let reprocessDocuments = Notification.Name("reprocessDocuments")
    static let documentsDeleted   = Notification.Name("documentsDeleted")
    static let scanDocumentVault  = Notification.Name("scanDocumentVault")
    static let toggleDocumentPreviewPane = Notification.Name("toggleDocumentPreviewPane")
    static let modelsDidChange    = Notification.Name("modelsDidChange")
    static let mlxBundlesDidChange = Notification.Name("mlxBundlesDidChange")
    static let tagsDidChange      = Notification.Name("tagsDidChange")
    static let scanFolderForImport = Notification.Name("scanFolderForImport")
    static let rebuildVectorIndex = Notification.Name("rebuildVectorIndex")
    static let autoScanFoldersDidChange = Notification.Name("autoScanFoldersDidChange")
}
