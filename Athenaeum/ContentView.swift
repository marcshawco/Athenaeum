import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Navigation
    @State private var selectedSection: SidebarSection = .all
    @State private var selectedTag: String?
    @State private var selectedDocument: Document?
    @State private var selectedDocuments: Set<Document> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var detailPanelMode: DetailPanelMode = .details

    // Services
    @State private var searchService = SearchService()
    @State private var modelManager = ModelManager()
    @State private var llmService: LocalLLMService?
    @State private var processor: DocumentProcessor?
    @State private var modelDownloader: ModelDownloader?
    @State private var vectorStore = VectorStore()
    @State private var ragService: RAGService?
    @State private var vaultMonitor = DocumentVaultMonitor()
    @State private var mlxManager = MLXModelManager()
    @AppStorage("inferenceEngine") private var inferenceEngineRaw: String = InferenceEngine.llamaCpp.rawValue

    // UI state
    @AppStorage("showDetailPanel") private var showDetailPanel = true
    @State private var showSettings = false
    @State private var showImportNotification = false
    @State private var importNotificationText = ""
    @State private var reindexCandidates: Int = 0
    @State private var isReindexing = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else {
                mainContent
            }
        }
        .onAppear {
            setupServices()
            // Sync column visibility with persisted panel preference on launch
            columnVisibility = showDetailPanel ? .all : .doubleColumn
        }
        .onReceive(NotificationCenter.default.publisher(for: .importDocuments)) { _ in
            openFilePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanFolderForImport)) { _ in
            openFolderForImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .reprocessDocuments)) { note in
            guard let docID = note.userInfo?["documentID"] as? UUID,
                  let processor else { return }
            let fetch = FetchDescriptor<Document>(
                predicate: #Predicate<Document> { $0.id == docID }
            )
            if let doc = try? modelContext.fetch(fetch).first {
                Task { await processor.reprocessDocuments([doc]) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentsDeleted)) { note in
            guard let docIDs = note.userInfo?["documentIDs"] as? [UUID] else { return }
            removeDeletedDocumentsFromUI(docIDs)

            guard let ragService else { return }
            Task {
                for docID in docIDs {
                    try? await ragService.removeDocument(id: docID)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDocumentPreviewPane)) { _ in
            togglePreviewPane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanDocumentVault)) { _ in
            scanDocumentVault(showNotification: true, announceNoChanges: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: DocumentVaultService.vaultDidChangeNotification)) { _ in
            restartVaultMonitor()
            scanDocumentVault(showNotification: true, announceNoChanges: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelsDidChange)) { _ in
            modelManager.scanForModels()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(modelManager: modelManager)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                VStack(spacing: 0) {
                    SidebarView(
                        selectedTag: $selectedTag,
                        selectedSection: $selectedSection
                    )

                    if let processor, let modelDownloader {
                        ProcessingQueueView(
                            processor: processor,
                            modelDownloader: modelDownloader
                        )
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: Japandi.Layout.sidebarWidth,
                    max: 280
                )
                // Force the sidebar column's own background to warm linen.
                // Without this, macOS paints the NavigationSplitView column with its
                // translucent grey sidebar material, which clashes with the cream content area.
                .background(Japandi.Colors.bgFallback)
            } detail: {
                contentColumn
                    // Native inspector panel slides in from the trailing edge.
                    // Toggled via View menu ▸ Show Inspector or ⌘⌥I — no toolbar clutter.
                    .inspector(isPresented: $showDetailPanel) {
                        detailColumn
                            .inspectorColumnWidth(min: Japandi.Layout.detailMinWidth,
                                                  ideal: 340,
                                                  max: 500)
                    }
            }
            .navigationSplitViewStyle(.balanced)

            stillwaterStatusBar
        }
        .frame(
            minWidth: Japandi.Layout.windowMinWidth,
            minHeight: Japandi.Layout.windowMinHeight
        )
        .overlay(alignment: .bottom) {
            notificationBanner
        }
        .overlay(alignment: .top) {
            reindexBanner
        }
        .spacePreviewShortcut()
        .task {
            await refreshReindexCandidates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentsDeleted)) { _ in
            Task { await refreshReindexCandidates() }
        }
    }

    // Banner — surfaced when the vector store has fewer indexed documents
    // than the library. Lets the user trigger a one-click re-index instead
    // of waiting for the launch-time auto-reconciler.
    @ViewBuilder
    private var reindexBanner: some View {
        if reindexCandidates > 0 {
            HStack(spacing: Japandi.Spacing.xs) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                Text("\(reindexCandidates) document\(reindexCandidates == 1 ? "" : "s") not yet indexed for search.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                Spacer(minLength: Japandi.Spacing.sm)
                if isReindexing {
                    ProgressView().controlSize(.small)
                    Text("Indexing…")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                } else {
                    Button("Re-index now") { reindexLibrary() }
                        .buttonStyle(.plain)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.accentFallback)
                }
                Button {
                    reindexCandidates = 0
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss re-index banner")
            }
            .padding(.horizontal, Japandi.Spacing.md)
            .padding(.vertical, 8)
            .background(Japandi.Colors.washFallback)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Japandi.Colors.borderFallback).frame(height: 0.5)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func refreshReindexCandidates() async {
        let fetch = FetchDescriptor<Document>()
        let docs = (try? modelContext.fetch(fetch)) ?? []
        let indexed = await vectorStore.indexedDocumentIDs
        let candidates = docs.filter { doc in
            doc.processingStatus == .complete
                && (doc.extractedText?.isEmpty == false)
                && !indexed.contains(doc.id)
        }
        await MainActor.run { reindexCandidates = candidates.count }
    }

    private func reindexLibrary() {
        guard let ragService else { return }
        isReindexing = true
        Task {
            let fetch = FetchDescriptor<Document>()
            let docs = (try? modelContext.fetch(fetch)) ?? []
            let indexed = await vectorStore.indexedDocumentIDs
            for doc in docs where doc.processingStatus == .complete
                && (doc.extractedText?.isEmpty == false)
                && !indexed.contains(doc.id) {
                if let text = doc.extractedText {
                    try? await ragService.indexDocument(id: doc.id, text: text)
                }
            }
            await refreshReindexCandidates()
            await MainActor.run { isReindexing = false }
        }
    }

    // Bottom status bar — local · private · model · index · sync.
    // Matches the Stillwater demo's footer rail.
    private var stillwaterStatusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Japandi.Colors.accentFallback)
                    .frame(width: 6, height: 6)
                Text("local · private")
            }
            Text("·").foregroundStyle(Japandi.Colors.textTertiaryFB)
            Text(modelManager.loadedModels.isEmpty ? "no model loaded" : "llama · loaded")
            Text("·").foregroundStyle(Japandi.Colors.textTertiaryFB)
            Text("vector index ready")
            Spacer()
            Text("last sync · just now")
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Japandi.Colors.textSecondaryFB)
        .padding(.horizontal, 18)
        .frame(height: 26)
        .background(Japandi.Colors.surfaceFallback)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Japandi.Colors.borderFallback)
                .frame(height: 0.5)
        }
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedSection {
        case .all, .recent, .processing, .untagged, .tag, .category:
            VStack(spacing: 0) {
                StatsDashboardView()
                Divider().foregroundStyle(Japandi.Colors.borderFallback)
                FilterBarView(searchService: searchService)
                DocumentGridView(
                    selectedDocument: $selectedDocument,
                    selectedDocuments: $selectedDocuments,
                    searchService: searchService,
                    section: selectedSection,
                    onImport: importFiles,
                    onReprocess: reprocessDocuments
                )
            }
        case .chat:
            if let ragService, let llmService {
                ChatView(llmService: llmService, ragService: ragService)
            } else {
                placeholderView("Setting up AI services...", icon: "cpu")
            }
        case .models:
            if let modelDownloader {
                ModelStatusView(
                    modelManager: modelManager,
                    modelDownloader: modelDownloader,
                    llmService: llmService
                )
            } else {
                placeholderView("Loading model manager...", icon: "cpu")
            }
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let selectedDocument {
            switch detailPanelMode {
            case .details:
                DocumentDetailView(document: selectedDocument)
            case .preview:
                DocumentPreviewWindow(document: selectedDocument, showsCloseButton: false)
            }
        } else {
            let text = detailPanelMode == .preview
                ? "Select a document to preview"
                : "Select a document to view details"
            placeholderView(text, icon: "doc.text.magnifyingglass")
        }
    }

    // MARK: - Notification Banner

    @ViewBuilder
    private var notificationBanner: some View {
        if showImportNotification {
            HStack(spacing: Japandi.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Japandi.Colors.accentFallback)
                Text(importNotificationText)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
            }
            .padding(.horizontal, Japandi.Spacing.md)
            .padding(.vertical, Japandi.Spacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .japandiShadow(Japandi.Shadow.card)
            .padding(.bottom, Japandi.Spacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private func placeholderView(_ text: String, icon: String) -> some View {
        VStack(spacing: Japandi.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            Text(text)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Japandi.Colors.bgFallback)
    }

    // MARK: - Setup

    private func setupServices() {
        guard processor == nil else { return }

        modelManager.scanForModels()
        mlxManager.scan()
        // We always instantiate `LocalLLMService` (it backs llama.cpp via the
        // already-bundled xcframework). The user-facing `inferenceEngine`
        // setting is observed here so we can log the selection and forward
        // it to services that need to differentiate. Once the MLX runtime
        // (mlx-swift SPM) is added, swap this for a protocol-typed
        // `LLMServiceProtocol` selected from the setting.
        let engine = InferenceEngine(rawValue: inferenceEngineRaw) ?? .llamaCpp
        if engine == .mlx && mlxManager.installedBundles.isEmpty {
            // Surface a hint that the bundle hasn't been downloaded yet.
            NSLog("[Athenaeum] MLX engine selected but no bundle installed; falling back to llama.cpp")
        }
        let service = LocalLLMService(modelManager: modelManager)
        llmService = service
        modelDownloader = ModelDownloader(modelsDirectory: modelManager.modelsDirectory)

        // RAG must be created before processor so it can be passed in
        let rag = RAGService(llmService: service, vectorStore: vectorStore)
        ragService = rag

        processor = DocumentProcessor(llmService: service, ragService: rag, modelContext: modelContext)
        _ = try? DocumentVaultService.shared.prepareVault()
        restartVaultMonitor()

        Task {
            try? await vectorStore.load()
            await reconcileDocumentsWithVault()
            // Re-index any already-processed documents the first time the vector store is empty
            await indexExistingDocumentsIfNeeded(ragService: rag)
            await scanDocumentVaultOnLaunch()
        }
    }

    @MainActor
    private func reconcileDocumentsWithVault() async {
        let fetch = FetchDescriptor<Document>()
        guard let docs = try? modelContext.fetch(fetch) else { return }

        var repairedCount = 0
        for doc in docs {
            if let url = doc.storedFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                continue
            }

            guard let data = doc.fileData else {
                if doc.processingStatus == .complete {
                    doc.processingStatus = .failed
                }
                doc.processingError = "Original file is missing from the vault and no backup data is available."
                doc.rebuildSearchableText()
                continue
            }

            do {
                let restoredURL = try DocumentVaultService.shared.storeData(data, preferredFilename: doc.originalFilename)
                doc.storagePath = restoredURL.path
                doc.processingError = nil
                doc.rebuildSearchableText()
                repairedCount += 1
            } catch {
                doc.processingError = "Could not restore original into the vault: \(error.localizedDescription)"
                doc.rebuildSearchableText()
            }
        }

        if repairedCount > 0 || docs.contains(where: { $0.processingError != nil }) {
            try? modelContext.save()
        }
        if repairedCount > 0 {
            await showBanner("\(repairedCount) original file\(repairedCount == 1 ? "" : "s") restored to vault")
        }
    }

    /// Background task: if the vector store is empty on launch, index every complete document.
    /// This handles documents that were imported before RAG indexing was wired up.
    @MainActor
    private func indexExistingDocumentsIfNeeded(ragService: RAGService) async {
        guard await vectorStore.totalEntries == 0 else { return }

        let fetch = FetchDescriptor<Document>()
        guard let docs = try? modelContext.fetch(fetch) else { return }

        for doc in docs {
            guard doc.processingStatus == .complete,
                  let text = doc.extractedText, !text.isEmpty else { continue }
            try? await ragService.indexDocument(id: doc.id, text: text)
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard let processor else { return }
        Task {
            let importedCount = await processor.importFiles(urls)

            if let error = processor.error {
                await showBanner(error)
            } else if importedCount == 0 {
                await showBanner("No new documents to import")
            } else {
                await showBanner("\(importedCount) document\(importedCount == 1 ? "" : "s") imported")
            }
        }
    }

    private func scanDocumentVault(showNotification: Bool, announceNoChanges: Bool = false) {
        Task {
            let count = await processor?.scanVaultForNewDocuments() ?? 0
            guard showNotification else { return }
            if let error = processor?.error {
                await showBanner(error)
            } else if count > 0 {
                await showBanner("\(count) new document\(count == 1 ? "" : "s") found in vault")
            } else if announceNoChanges {
                await showBanner("Document vault is up to date")
            }
        }
    }

    @MainActor
    private func scanDocumentVaultOnLaunch() async {
        let count = await processor?.scanVaultForNewDocuments() ?? 0
        if count > 0 {
            await showBanner("\(count) new document\(count == 1 ? "" : "s") found in vault")
        } else if let error = processor?.error {
            await showBanner(error)
        }
    }

    private func restartVaultMonitor() {
        let vaultURL = DocumentVaultService.shared.vaultURL
        vaultMonitor.start(watching: vaultURL) {
            scanDocumentVault(showNotification: true)
        }
        if let error = vaultMonitor.lastError {
            Task { await showBanner(error) }
        }
    }

    @MainActor
    private func showBanner(_ message: String) async {
        importNotificationText = message
        withAnimation(Japandi.Motion.gentle) { showImportNotification = true }
        try? await Task.sleep(for: .seconds(3))
        withAnimation(Japandi.Motion.gentle) { showImportNotification = false }
    }

    private func reprocessDocuments(_ documents: [Document]) {
        guard let processor else { return }
        Task {
            await processor.reprocessDocuments(documents)
        }
    }

    private func togglePreviewPane() {
        if detailPanelMode == .preview {
            detailPanelMode = .details
            showDetailPanel = true
        } else {
            detailPanelMode = .preview
            showDetailPanel = true
            columnVisibility = .all
        }
    }

    private func removeDeletedDocumentsFromUI(_ docIDs: [UUID]) {
        let deletedIDs = Set(docIDs)
        if let selectedDocument, deletedIDs.contains(selectedDocument.id) {
            self.selectedDocument = nil
        }
        selectedDocuments = selectedDocuments.filter { !deletedIDs.contains($0.id) }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .rtfd, .image, .audio, .movie, .data]
        panel.message = "Select documents to import into Athenaeum"
        panel.directoryURL = DocumentVaultService.shared.vaultURL

        if panel.runModal() == .OK {
            importFiles(panel.urls)
        }
    }

    /// Recursively walk a folder the user picks and import every file with a
    /// supported extension. Powers File ▸ Scan Folder for Import (⇧⌘I).
    private func openFolderForImport() {
        let panel = NSOpenPanel()
        panel.title = "Scan Folder for Import"
        panel.message = "Pick a folder. Every supported document found inside will be imported."
        panel.prompt = "Scan & Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        // Walk the folder. We rely on the same extension allow-list as the
        // single-file picker to avoid sucking in random binaries.
        let allowedExtensions: Set<String> = [
            "pdf", "txt", "rtf", "rtfd", "doc", "docx", "md", "html", "htm",
            "png", "jpg", "jpeg", "tif", "tiff", "heic", "webp", "gif", "bmp"
        ]

        Task.detached(priority: .userInitiated) {
            var urls: [URL] = []
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                if allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    urls.append(fileURL)
                }
            }
            await MainActor.run {
                if urls.isEmpty {
                    Task { await showBanner("No supported documents found in folder") }
                } else {
                    importFiles(urls)
                }
            }
        }
    }
}

private enum DetailPanelMode {
    case details
    case preview
}

#Preview {
    ContentView()
        .modelContainer(for: [Document.self, Tag.self], inMemory: true)
}
