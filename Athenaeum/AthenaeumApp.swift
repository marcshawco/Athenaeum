import SwiftUI
import SwiftData

@main
struct AthenaeumApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    init() {
        // Re-apply the user's chosen app-icon variant on every cold launch
        // so the Dock + Cmd-Tab tile match what they picked in Settings.
        AppIconApplier.applyFromDefaults()

        // On first launch, push tier-aware defaults (chunk size, top-K,
        // n_ctx, GPU layers, char budgets) into UserDefaults so a brand
        // new install runs at the right shape for this Mac. Subsequent
        // launches respect whatever the user has tuned by hand or via
        // the Settings tier picker.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didApplyInitialHardwareTunables") {
            HardwareProfiler.applyTunablesForActiveTier()
            defaults.set(true, forKey: "didApplyInitialHardwareTunables")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
                .tint(Japandi.Colors.accentFallback)
        }
        .modelContainer(for: [Document.self, Tag.self, ChatConversation.self, KnowledgeEntry.self, Folder.self])
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
    /// Sent when a chat source is clicked. userInfo["documentID"] = UUID.
    /// ContentView routes back to the library and selects the target.
    static let selectDocumentByID = Notification.Name("selectDocumentByID")
    /// Posted by the inspector's close (✕) button.
    static let closeInspector = Notification.Name("closeInspector")
    /// userInfo["documentIDs"] = [UUID] — kick off the AI-rename flow for
    /// one or more documents. ContentView shows the review sheet.
    static let aiRenameDocuments = Notification.Name("aiRenameDocuments")
    /// Posted when the user picks a new app-icon variant in Settings.
    /// SwiftUI views that show the brand mark observe this to redraw.
    static let appIconVariantDidChange = Notification.Name("appIconVariantDidChange")
    /// Posted by `HardwareProfiler` when the resolved/active tier changes.
    /// Inference and RAG layers re-read their tier-aware defaults.
    static let hardwareTierDidChange = Notification.Name("hardwareTierDidChange")
}
