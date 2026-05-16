import SwiftUI
import SwiftData
import QuickLook

struct DocumentContextMenu: ViewModifier {
    let document: Document
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var quickLookURL: URL?
    @State private var quickLookTempURL: URL?
    @State private var showInAppPreview = false

    func body(content: Content) -> some View {
        content
            .quickLookPreview($quickLookURL)
            .onChange(of: quickLookURL) { _, newValue in
                if newValue == nil {
                    cleanupQuickLookTemp()
                }
            }
            .sheet(isPresented: $showInAppPreview) {
                DocumentPreviewWindow(document: document)
                    .frame(minWidth: 760, idealWidth: 960, minHeight: 620, idealHeight: 760)
            }
            .contextMenu {
                // Open
                Button {
                    showInAppPreview = true
                } label: {
                    Label("View in Athenaeum", systemImage: "doc.richtext")
                }

                Button {
                    openInQuickLook()
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }

                Button {
                    openInDefaultApp()
                } label: {
                    Label("Open in Default App", systemImage: "arrow.up.forward.app")
                }

                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .disabled(existingStoredURL == nil)

                Divider()

                // Export
                Button {
                    exportDocument()
                } label: {
                    Label("Export Original...", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyExtractedText()
                } label: {
                    Label("Copy Extracted Text", systemImage: "doc.on.clipboard")
                }
                .disabled(document.extractedText == nil)

                Divider()

                // Processing
                Button {
                    reprocessDocument()
                } label: {
                    Label("Reprocess", systemImage: "arrow.clockwise")
                }

                Divider()

                // Destructive
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .alert("Delete Document?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteDocument()
                }
            } message: {
                Text("This removes \"\(document.title)\" from Athenaeum. Its vault file will be moved to Trash when available.")
            }
    }

    private func openInQuickLook() {
        if let url = existingStoredURL {
            quickLookURL = url
            return
        }
        guard let data = document.fileData else { return }
        let tempURL = temporaryURL(for: document)
        do {
            try data.write(to: tempURL, options: .atomic)
            quickLookTempURL = tempURL
            quickLookURL = tempURL
        } catch {
            cleanupQuickLookTemp()
        }
    }

    private func openInDefaultApp() {
        if let url = existingStoredURL {
            NSWorkspace.shared.open(url)
            return
        }
        guard let data = document.fileData else { return }
        let tempURL = temporaryURL(for: document)
        do {
            try data.write(to: tempURL, options: .atomic)
            NSWorkspace.shared.open(tempURL)
        } catch {
            NSSound.beep()
        }
    }

    private func revealInFinder() {
        guard let url = existingStoredURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportDocument() {
        guard let data = availableFileData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.originalFilename
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func copyExtractedText() {
        guard let text = document.extractedText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func reprocessDocument() {
        // Reset state first, then notify ContentView to run the real pipeline
        document.processingStatus = .pending
        document.processingError = nil
        document.extractedText = nil
        document.summary = nil
        document.tags?.removeAll()
        document.modifiedAt = .now
        document.rebuildSearchableText()
        try? modelContext.save()
        NotificationCenter.default.post(
            name: .reprocessDocuments,
            object: nil,
            userInfo: ["documentID": document.id]
        )
    }

    private func deleteDocument() {
        let deletedID = document.id
        if let url = existingStoredURL {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        cleanupQuickLookTemp()
        modelContext.delete(document)
        try? modelContext.save()
        NotificationCenter.default.post(
            name: .documentsDeleted,
            object: nil,
            userInfo: ["documentIDs": [deletedID]]
        )
    }

    private func temporaryURL(for document: Document) -> URL {
        let ext = document.fileExtension
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("athenaeum-\(document.id.uuidString)")
        return ext.isEmpty ? base : base.appendingPathExtension(ext)
    }

    private func cleanupQuickLookTemp() {
        if let quickLookTempURL {
            try? FileManager.default.removeItem(at: quickLookTempURL)
            self.quickLookTempURL = nil
        }
    }

    private var existingStoredURL: URL? {
        guard let url = document.storedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private var availableFileData: Data? {
        if let url = existingStoredURL, let data = try? Data(contentsOf: url) {
            return data
        }
        return document.fileData
    }
}

extension View {
    func documentContextMenu(document: Document) -> some View {
        modifier(DocumentContextMenu(document: document))
    }
}
