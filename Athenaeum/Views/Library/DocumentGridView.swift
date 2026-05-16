import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentGridView: View {
    @Query private var allDocuments: [Document]
    @Binding var selectedDocument: Document?
    @Binding var selectedDocuments: Set<Document>
    @Bindable var searchService: SearchService
    var section: SidebarSection
    var onImport: ([URL]) -> Void
    var onReprocess: (([Document]) -> Void)?

    @State private var isDropTargeted = false
    @State private var viewMode: ViewMode = .grid
    @State private var showBatchTagSheet = false
    @State private var newBatchTag = ""
    @AppStorage("defaultViewMode") private var defaultViewMode = ViewMode.grid.rawValue
    @Environment(\.modelContext) private var modelContext

    enum ViewMode: String, CaseIterable {
        case grid, list
    }

    init(
        selectedDocument: Binding<Document?>,
        selectedDocuments: Binding<Set<Document>>,
        searchService: SearchService,
        section: SidebarSection,
        onImport: @escaping ([URL]) -> Void,
        onReprocess: (([Document]) -> Void)? = nil
    ) {
        self._selectedDocument = selectedDocument
        self._selectedDocuments = selectedDocuments
        self.searchService = searchService
        self.section = section
        self.onImport = onImport
        self.onReprocess = onReprocess
    }

    // Apply section filter first, then search/tag/date filters
    var filteredDocuments: [Document] {
        let sectionFiltered = searchService.filterBySection(allDocuments, section: section)
        return searchService.filter(sectionFiltered)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            // Batch toolbar — slides in when anything is selected
            if !selectedDocuments.isEmpty {
                Rectangle()
                    .fill(Japandi.Colors.borderFallback.opacity(0.8))
                    .frame(height: 0.5)
                BatchActionToolbar(
                    selectedCount: selectedDocuments.count,
                    onAddTag: { showBatchTagSheet = true },
                    onExport: { batchExport() },
                    onReprocess: { batchReprocess() },
                    onDelete: { batchDelete() },
                    onClearSelection: { selectedDocuments.removeAll() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(Japandi.Motion.snappy, value: selectedDocuments.isEmpty)
            }

            Rectangle()
                .fill(Japandi.Colors.borderFallback.opacity(0.8))
                .frame(height: 0.5)

            if filteredDocuments.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .grid: gridContent
                case .list: listContent
                }
            }
        }
        .background(Japandi.Colors.bgFallback)
        .onDrop(of: DocumentDropDelegate.supportedTypes, delegate: DocumentDropDelegate(
            onDrop: onImport,
            isTargeted: $isDropTargeted
        ))
        .overlay {
            if isDropTargeted { dropOverlay }
        }
        .sheet(isPresented: $showBatchTagSheet) {
            batchTagSheet
        }
        .onAppear {
            viewMode = ViewMode(rawValue: defaultViewMode) ?? .grid
        }
        .onChange(of: defaultViewMode) {
            viewMode = ViewMode(rawValue: defaultViewMode) ?? .grid
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            SearchBarView(text: $searchService.query)
                .frame(maxWidth: 400)

            Spacer()

            Menu {
                ForEach(SearchService.SortOrder.allCases, id: \.self) { order in
                    Button(order.rawValue) { searchService.sortOrder = order }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Button(action: openFilePicker) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("Import")
                        .font(Japandi.Typography.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Japandi.Spacing.sm)
                .frame(height: 28)
                .background(Japandi.Colors.inkFallback)
                .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Japandi.Spacing.lg)
        .padding(.vertical, Japandi.Spacing.sm)
    }

    // MARK: - Grid

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: Japandi.Spacing.lg)],
                spacing: Japandi.Spacing.lg
            ) {
                ForEach(filteredDocuments) { document in
                    let isItemSelected = selectedDocuments.contains(document)
                    DocumentCardView(
                        document: document,
                        isSelected: selectedDocument?.id == document.id || isItemSelected
                    )
                    .documentContextMenu(document: document)
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if isItemSelected {
                                selectedDocuments.remove(document)
                                if selectedDocument?.id == document.id {
                                    selectedDocument = selectedDocuments.first
                                }
                            } else {
                                selectedDocuments.insert(document)
                                selectedDocument = document
                            }
                        } else {
                            selectedDocuments.removeAll()
                            selectedDocument = document
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isItemSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Japandi.Colors.accentFallback)
                                .background(Japandi.Colors.surfaceRaisedFB.clipShape(Circle()))
                                .padding(Japandi.Spacing.xs)
                        }
                    }
                }
            }
            .padding(.horizontal, Japandi.Spacing.lg)
            .padding(.vertical, Japandi.Spacing.lg)
        }
    }

    // MARK: - List

    private var listContent: some View {
        List(filteredDocuments, selection: $selectedDocument) { document in
            DocumentRowView(document: document)
                .tag(document)
                .documentContextMenu(document: document)
        }
        .listStyle(.inset)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Japandi.Spacing.xl) {
            Spacer()
            Image(systemName: emptyStateIcon)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.borderFallback)
            VStack(spacing: Japandi.Spacing.xs) {
                Text(emptyStateTitle)
                    .font(Japandi.Typography.title)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text(emptyStateSubtitle)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        switch section {
        case .untagged:   return "tag.slash"
        case .recent:     return "clock"
        case .processing: return "gearshape.2"
        case .tag:        return "tag"
        default:          return "doc.badge.plus"
        }
    }

    private var emptyStateTitle: String {
        switch section {
        case .untagged:   return "No Untagged Documents"
        case .recent:     return "Nothing This Week"
        case .processing: return "All Caught Up"
        case .tag(let t): return "No \"\(t.capitalized)\" Documents"
        default:
            return searchService.hasActiveFilters ? "No Results" : "No Documents"
        }
    }

    private var emptyStateSubtitle: String {
        switch section {
        case .untagged:   return "All documents have tags"
        case .recent:     return "No documents imported in the last 7 days"
        case .processing: return "Nothing is currently being processed"
        case .tag:        return "No documents match this tag"
        default:
            return searchService.hasActiveFilters
                ? "Try adjusting your search or filters"
                : "Drop files here or click Import"
        }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: Japandi.Radius.lg, style: .continuous)
            .strokeBorder(Japandi.Colors.accentFallback.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [10, 5]))
            .background(
                Japandi.Colors.accentFallback.opacity(0.04)
                    .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.lg, style: .continuous))
            )
            .overlay {
                VStack(spacing: Japandi.Spacing.sm) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(Japandi.Colors.accentFallback)
                    Text("Drop to import")
                        .font(Japandi.Typography.title)
                        .foregroundStyle(Japandi.Colors.accentFallback)
                }
            }
            .padding(Japandi.Spacing.lg)
            .transition(.opacity)
            .animation(Japandi.Motion.gentle, value: isDropTargeted)
    }

    // MARK: - Batch Tag Sheet

    private var batchTagSheet: some View {
        VStack(spacing: Japandi.Spacing.lg) {
            Text("Add Tag to \(selectedDocuments.count) Documents")
                .font(Japandi.Typography.headline)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            TextField("Tag name", text: $newBatchTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit { applyBatchTag() }

            HStack {
                Button("Cancel") { showBatchTagSheet = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                Spacer()
                Button("Apply") { applyBatchTag() }
                    .buttonStyle(.borderedProminent)
                    .tint(Japandi.Colors.accentFallback)
                    .disabled(newBatchTag.isEmpty)
            }
        }
        .padding(Japandi.Spacing.xl)
        .frame(width: 320)
        .background(Japandi.Colors.bgFallback)
    }

    // MARK: - Batch Actions

    private func applyBatchTag() {
        let name = newBatchTag.lowercased().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let processor = BatchProcessor(modelContext: modelContext)
        processor.addTag(name, to: Array(selectedDocuments))
        selectedDocuments.removeAll()
        newBatchTag = ""
        showBatchTagSheet = false
    }

    private func batchExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        if panel.runModal() == .OK, let url = panel.url {
            let processor = BatchProcessor(modelContext: modelContext)
            processor.exportDocuments(Array(selectedDocuments), to: url)
        }
        selectedDocuments.removeAll()
    }

    private func batchReprocess() {
        let docs = Array(selectedDocuments)
        selectedDocuments.removeAll()
        if let onReprocess {
            onReprocess(docs)
        } else {
            let processor = BatchProcessor(modelContext: modelContext)
            processor.reprocessDocuments(docs)
        }
    }

    private func batchDelete() {
        let processor = BatchProcessor(modelContext: modelContext)
        if selectedDocument.map({ selectedDocuments.contains($0) }) == true {
            selectedDocument = nil
        }
        processor.deleteDocuments(Array(selectedDocuments))
        selectedDocuments.removeAll()
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .rtfd, .image, .audio, .movie, .data]
        panel.message = "Select documents to import into Athenaeum"
        if panel.runModal() == .OK { onImport(panel.urls) }
    }
}

// MARK: - Document Card View

struct DocumentCardView: View {
    let document: Document
    var isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            ZStack(alignment: .topTrailing) {
                Japandi.Colors.surfaceFallback

                DocumentThumbnailView(
                    document: document,
                    size: CGSize(width: 210, height: 148),
                    normalizesDocumentSize: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(document.fileExtension.uppercased().isEmpty ? "FILE" : document.fileExtension.uppercased())
                    .font(Japandi.Typography.eyebrow)
                    .tracking(1)
                    .foregroundStyle(Japandi.Colors.surfaceRaisedFB)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Japandi.Colors.inkFallback.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
                    .padding(Japandi.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipped()

            // Fixed-height title block — always reserves space for 2 lines so
            // single- and double-line titles render at the same card height.
            VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
                Text(document.title)
                    .font(Japandi.Typography.headline)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36, alignment: .topLeading)

                HStack(spacing: Japandi.Spacing.xxs) {
                    Text(document.fileSizeFormatted)
                    if let docDate = document.documentDate {
                        Text("·")
                        Text(docDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            // Fixed-height tag/status footer — always one row, never wraps.
            HStack(spacing: Japandi.Spacing.xxs) {
                if document.processingStatus == .failed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Japandi.Colors.lacquerFallback)
                    Text(document.processingError?.nilIfBlank ?? "Processing failed")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.lacquerFallback)
                        .lineLimit(1)
                } else if document.processingStatus != .complete {
                    ProgressView().scaleEffect(0.5)
                    Text(document.processingStatus.rawValue.capitalized)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                } else if let tags = document.tags, !tags.isEmpty {
                    ForEach(tags.prefix(2)) { tag in
                        TagPillView(name: tag.name, colorHex: tag.colorHex)
                    }
                    if tags.count > 2 {
                        Text("+\(tags.count - 2)")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            .clipped()
        }
        .padding(Japandi.Spacing.md)
        .frame(height: 290)
        .japandiCardHover(isHovered || isSelected)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Japandi.Radius.md, style: .continuous)
                    .strokeBorder(Japandi.Colors.accentFallback.opacity(0.75), lineWidth: 1)
            }
        }
        .scaleEffect(isHovered ? 1.008 : 1)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Document Row View

struct DocumentRowView: View {
    let document: Document

    var body: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                    .fill(Japandi.Colors.surfaceFallback)
                    .overlay(
                        RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                            .strokeBorder(Japandi.Colors.borderFallback.opacity(0.8), lineWidth: 0.5)
                    )
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.accentFallback)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                HStack(spacing: Japandi.Spacing.xs) {
                    Text(document.fileSizeFormatted)
                    Text("·")
                    Text(document.importedAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            Spacer()

            if let tags = document.tags {
                HStack(spacing: Japandi.Spacing.xxs) {
                    ForEach(tags.prefix(2)) { tag in
                        TagPillView(name: tag.name, colorHex: tag.colorHex)
                    }
                }
            }
        }
        .padding(.vertical, Japandi.Spacing.xs)
        .padding(.horizontal, Japandi.Spacing.xs)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
