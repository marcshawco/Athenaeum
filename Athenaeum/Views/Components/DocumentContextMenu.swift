import SwiftUI
import SwiftData
import QuickLook

struct DocumentContextMenu: ViewModifier {
    let document: Document
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @State private var showDeleteConfirmation = false
    @State private var quickLookURL: URL?
    @State private var quickLookTempURL: URL?
    @State private var showInAppPreview = false
    @State private var showAddTagSheet = false
    @State private var newTagText: String = ""
    @State private var showFolderCreator = false

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
                    Label("View in ATHENS", systemImage: "doc.richtext")
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

                // Copy submenu — covers every shape of "get this somewhere else".
                Menu {
                    Button {
                        copyFileToPasteboard()
                    } label: {
                        Label("Copy File", systemImage: "doc.on.doc")
                    }
                    .disabled(existingStoredURL == nil)

                    Button {
                        copyFilePath()
                    } label: {
                        Label("Copy File Path", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .disabled(existingStoredURL == nil)

                    Button {
                        copyTitle()
                    } label: {
                        Label("Copy Title", systemImage: "textformat")
                    }

                    Button {
                        copyExtractedText()
                    } label: {
                        Label("Copy Extracted Text", systemImage: "doc.on.clipboard")
                    }
                    .disabled(document.extractedText == nil)

                    if let summary = document.summary, !summary.isEmpty {
                        Button {
                            copyToPasteboard(summary)
                        } label: {
                            Label("Copy Summary", systemImage: "text.alignleft")
                        }
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                // Share — native macOS Share Sheet (Mail, Messages, AirDrop, etc.)
                Button {
                    presentShareSheet()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(existingStoredURL == nil && document.fileData == nil)

                // Export
                Button {
                    exportDocument()
                } label: {
                    Label("Export Original", systemImage: "tray.and.arrow.up")
                }

                Divider()

                // Processing
                Button {
                    NotificationCenter.default.post(
                        name: .aiRenameDocuments,
                        object: nil,
                        userInfo: ["documentIDs": [document.id]]
                    )
                } label: {
                    Label("Auto Name", systemImage: "sparkles")
                }
                .disabled(document.extractedText?.isEmpty != false)

                Button {
                    reprocessDocument()
                } label: {
                    Label("Auto Tag", systemImage: "wand.and.stars")
                }

                Button {
                    newTagText = ""
                    showAddTagSheet = true
                } label: {
                    Label("Add Tag", systemImage: "tag.fill")
                }

                // Add-to-Folder submenu — list every folder, then a
                // "New folder…" affordance at the bottom for the create
                // flow. Existing folders that already contain this doc
                // show a checkmark and toggle membership off on click.
                Menu {
                    if allFolders.isEmpty {
                        Text("No folders yet")
                    } else {
                        ForEach(allFolders) { folder in
                            Button {
                                toggleMembership(in: folder)
                            } label: {
                                Label(
                                    folder.name,
                                    systemImage: isMember(of: folder) ? "checkmark.circle.fill" : "folder"
                                )
                            }
                        }
                    }
                    Divider()
                    Button {
                        showFolderCreator = true
                    } label: {
                        Label("New folder…", systemImage: "plus")
                    }
                } label: {
                    Label("Add to Folder", systemImage: "folder")
                }

                Button {
                    clearTags()
                } label: {
                    Label("Clear Tags", systemImage: "tag.slash")
                }
                .disabled((document.tags ?? []).isEmpty)

                Divider()

                // Destructive
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showAddTagSheet) {
                addTagSheet
            }
            .sheet(isPresented: $showFolderCreator) {
                FolderEditorSheet(folder: nil) {
                    showFolderCreator = false
                }
            }
            .alert("Delete Document?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteDocument()
                }
            } message: {
                Text("This removes \"\(document.title)\" from ATHENS. Its vault file will be moved to Trash when available.")
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
        copyToPasteboard(text)
    }

    /// Writes the file URL onto the pasteboard so the user can paste it into
    /// Finder, Mail, Messages, etc. — same as Cmd-C on a file in Finder.
    private func copyFileToPasteboard() {
        guard let url = existingStoredURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// Copies the absolute filesystem path as a plain string. Useful for
    /// pasting into Terminal or a `cd` prompt.
    private func copyFilePath() {
        guard let url = existingStoredURL else { return }
        copyToPasteboard(url.path)
    }

    private func copyTitle() {
        copyToPasteboard(document.title)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens the macOS Share Sheet anchored to the key window. Works for
    /// AirDrop, Mail, Messages, Notes, and any third-party share extension.
    private func presentShareSheet() {
        let urlToShare: URL?
        if let stored = existingStoredURL {
            urlToShare = stored
        } else if let data = document.fileData {
            let tempURL = temporaryURL(for: document)
            try? data.write(to: tempURL, options: .atomic)
            urlToShare = tempURL
        } else {
            urlToShare = nil
        }
        guard let url = urlToShare else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    // Small modal for typing a new tag. Lives here (in the menu modifier)
    // so right-click → Add Tag… → Enter is a 3-key flow with no detours.
    private var addTagSheet: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add tag")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text("Reuse an existing tag by name, or invent a new one. Tags use kebab-case.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            TextField("e.g. tax-2025", text: $newTagText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitNewTag() }

            HStack {
                Spacer()
                Button("Cancel") {
                    showAddTagSheet = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    commitNewTag()
                }
                .buttonStyle(.borderedProminent)
                .tint(Japandi.Colors.accentFallback)
                .keyboardShortcut(.defaultAction)
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Japandi.Spacing.lg)
        .frame(width: 340)
    }

    /// Normalize the typed name, find or create the Tag row, and attach it.
    /// Posts `.tagsDidChange` so the sidebar / library count refresh.
    private func commitNewTag() {
        let normalized = newTagText
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "-")
        guard !normalized.isEmpty else { return }

        let predicate = #Predicate<Tag> { $0.name == normalized }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let existing = try? modelContext.fetch(descriptor).first

        let tag = existing ?? Tag(
            name: normalized,
            colorHex: Tag.defaultColors.randomElement() ?? "3E5C4A"
        )
        if existing == nil { modelContext.insert(tag) }

        if document.tags == nil { document.tags = [] }
        if !(document.tags?.contains(where: { $0.name == normalized }) ?? false) {
            document.tags?.append(tag)
        }
        document.modifiedAt = .now
        document.rebuildSearchableText()
        try? modelContext.save()

        newTagText = ""
        showAddTagSheet = false
        NotificationCenter.default.post(name: .tagsDidChange, object: nil)
    }

    private func isMember(of folder: Folder) -> Bool {
        document.folders?.contains(where: { $0.id == folder.id }) == true
    }

    /// Add or remove the document from a folder. SwiftData manages the
    /// inverse relationship; we just mutate the array on either side.
    private func toggleMembership(in folder: Folder) {
        if document.folders == nil { document.folders = [] }
        if isMember(of: folder) {
            document.folders?.removeAll { $0.id == folder.id }
        } else {
            document.folders?.append(folder)
        }
        document.modifiedAt = .now
        try? modelContext.save()
    }

    /// Strip every tag attachment off this document without touching the
    /// Tag rows themselves (other documents may still own them). Useful when
    /// the LLM mis-tagged something and you want to start fresh.
    private func clearTags() {
        document.tags?.removeAll()
        document.modifiedAt = .now
        document.rebuildSearchableText()
        try? modelContext.save()
        NotificationCenter.default.post(name: .tagsDidChange, object: nil)
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
