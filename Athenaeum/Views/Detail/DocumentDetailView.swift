import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var newTagName: String = ""
    @State private var showPreview = false
    @State private var isEditingDocumentDate = false
    @State private var editedDocumentDate = Date.now
    @State private var showTypePicker = false

    var body: some View {
        // Split the inspector into a scrollable metadata column at the top
        // and a "full-bleed" preview pane at the bottom that fills whatever
        // height is left. Feels like an integrated document viewer instead
        // of a tiny preview tile floating in an ocean of empty space.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    inspectorRule
                    metadataSection
                    inspectorRule
                    tagsSection
                    inspectorRule
                    summarySection
                }
            }
            .layoutPriority(0)

            inspectorRule

            previewSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .background(Japandi.Colors.inspectorBg)
        .sheet(isPresented: $showPreview) {
            DocumentPreviewWindow(document: document)
                .frame(minWidth: 760, idealWidth: 960, minHeight: 620, idealHeight: 760)
        }
        .sheet(isPresented: $showTypePicker) {
            DocumentTypePicker(currentSlug: document.documentTypeSlug) { selected in
                if let type = selected {
                    document.documentTypeSlug = type.slug
                    document.categorySlug = DocumentTaxonomy.category(containingTypeSlug: type.slug)?.slug
                } else {
                    document.documentTypeSlug = nil
                    document.categorySlug = nil
                }
                document.modifiedAt = .now
                document.rebuildSearchableText()
                try? modelContext.save()
                showTypePicker = false
            } onCancel: {
                showTypePicker = false
            }
        }
    }

    private var inspectorRule: some View {
        Rectangle()
            .fill(Japandi.Colors.inspectorRule)
            .frame(height: 0.5)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .center) {
                Text("Document · Selected")
                    .font(Japandi.Typography.eyebrow)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Japandi.Colors.inspectorInk3)
                Spacer()
                // Close the inspector. Lives at the very top right of the
                // dark-moss panel so it's predictable and matches the
                // chrome of every other panel in the app.
                Button {
                    NotificationCenter.default.post(name: .closeInspector, object: nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Japandi.Colors.inspectorInk2)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                                .overlay(Circle().strokeBorder(Japandi.Colors.inspectorRule, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Close inspector")
                .accessibilityLabel("Close inspector")
                .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top) {
                if isEditing {
                    TextField("Document title", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .light, design: .serif))
                        .foregroundStyle(Japandi.Colors.inspectorInk)
                        .onSubmit { saveTitleEdit() }
                } else {
                    Text(document.title)
                        .font(.system(size: 17, weight: .light, design: .serif))
                        .foregroundStyle(Japandi.Colors.inspectorInk)
                        .lineSpacing(2)
                }

                Spacer()

                HStack(spacing: Japandi.Spacing.xs) {
                    Button {
                        if isEditing {
                            saveTitleEdit()
                        } else {
                            editedTitle = document.title
                            isEditing = true
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(Japandi.Colors.inspectorInk3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showPreview = true
                    } label: {
                        Text("Open")
                            .font(.system(size: 10.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Japandi.Colors.inspectorAccent)
                            .foregroundStyle(Japandi.Colors.inspectorBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Japandi.Spacing.xs) {
                statusBadge

                Text(document.originalFilename)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.inspectorInk3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Taxonomy badge — resolved Document Type and parent Category from
            // the local LLM, anchored to the canonical 500-type reference list.
            // Click to override with a searchable picker over all 500 types.
            Button {
                showTypePicker = true
            } label: {
                HStack(spacing: Japandi.Spacing.xxs) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 9))
                        .foregroundStyle(Japandi.Colors.inspectorAccent)
                    Text(document.documentTypeName ?? "Set document type…")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(document.documentTypeName != nil
                                         ? Japandi.Colors.inspectorInk
                                         : Japandi.Colors.inspectorInk3)
                    if let categoryName = document.categoryName {
                        Text("·")
                            .foregroundStyle(Japandi.Colors.inspectorInk3)
                        Text(categoryName)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Japandi.Colors.inspectorInk2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Japandi.Colors.inspectorInk3)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Japandi.Colors.inspectorRule, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Choose the document type from the 500-type taxonomy")
            .accessibilityLabel("Edit document type")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBadge: some View {
        HStack(spacing: Japandi.Spacing.xxs) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(document.processingStatus.rawValue.capitalized)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.inspectorInk2)
        }
        .padding(.horizontal, Japandi.Spacing.xs)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.18))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.35), lineWidth: 0.5))
    }

    private var statusColor: Color {
        switch document.processingStatus {
        case .complete: Japandi.Colors.inspectorAccent
        case .failed:   Japandi.Colors.warmFallback
        case .pending:  Japandi.Colors.inspectorInk3
        default:        Japandi.Colors.inspectorAccent
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            Text("Metadata")
                .font(Japandi.Typography.eyebrow)
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Japandi.Colors.inspectorInk3)
                .padding(.bottom, 4)

            MetadataRow(label: "File Type", value: document.fileExtension.uppercased())
            MetadataRow(label: "Size", value: document.fileSizeFormatted)
            MetadataRow(label: "Imported", value: document.importedAt.formatted(date: .long, time: .shortened))
            documentDateRow

            if let correspondent = document.correspondent {
                MetadataRow(label: "Correspondent", value: correspondent)
            }

            if let storedURL = existingStoredURL {
                HStack(alignment: .top) {
                    Text("Vault File")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.inspectorInk3)
                        .frame(width: 100, alignment: .leading)

                    Text(storedURL.path)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.inspectorInk2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([storedURL])
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Japandi.Colors.inspectorAccent)
                    .font(Japandi.Typography.caption)
                }
            }

            if document.processingStatus == .failed,
               let processingError = document.processingError?.nilIfBlank {
                VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
                    Text("Processing Error")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.warmFallback)
                    Text(processingError)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.inspectorInk2)
                        .textSelection(.enabled)
                }
                .padding(Japandi.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Japandi.Colors.warmFallback.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                        .strokeBorder(Japandi.Colors.warmFallback.opacity(0.25), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var existingStoredURL: URL? {
        guard let url = document.storedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private var documentDateRow: some View {
        HStack(alignment: .center, spacing: Japandi.Spacing.xs) {
            Text("Document Date")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.inspectorInk3)
                .frame(width: 100, alignment: .leading)

            if isEditingDocumentDate {
                DatePicker("", selection: $editedDocumentDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)

                Button("Save") {
                    document.documentDate = editedDocumentDate
                    document.modifiedAt = .now
                    document.rebuildSearchableText()
                    try? modelContext.save()
                    isEditingDocumentDate = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.inspectorAccent)
                .font(Japandi.Typography.caption)

                Button("Clear") {
                    document.documentDate = nil
                    document.modifiedAt = .now
                    document.rebuildSearchableText()
                    try? modelContext.save()
                    isEditingDocumentDate = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.inspectorInk3)
                .font(Japandi.Typography.caption)
            } else {
                Text(document.documentDate?.formatted(date: .long, time: .omitted) ?? "Not set")
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.inspectorInk2)

                Button(document.documentDate == nil ? "Add" : "Edit") {
                    editedDocumentDate = document.documentDate ?? .now
                    isEditingDocumentDate = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.inspectorAccent)
                .font(Japandi.Typography.caption)
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            Text("Tags")
                .font(Japandi.Typography.eyebrow)
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Japandi.Colors.inspectorInk3)

            FlowLayout(spacing: Japandi.Spacing.xs) {
                if let tags = document.tags {
                    ForEach(tags) { tag in
                        TagPillView(
                            name: tag.name,
                            colorHex: tag.colorHex,
                            onRemove: { removeTag(tag) }
                        )
                    }
                }

                // Add tag field
                HStack(spacing: Japandi.Spacing.xxs) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Japandi.Colors.inspectorInk3)
                    TextField("Add tag", text: $newTagName)
                        .textFieldStyle(.plain)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.inspectorInk2)
                        .frame(width: 72)
                        .onSubmit { addTag() }
                }
                .padding(.horizontal, Japandi.Spacing.xs)
                .padding(.vertical, Japandi.Spacing.xxs)
                .overlay(
                    Capsule()
                        .strokeBorder(Japandi.Colors.inspectorInk3.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary (scrolls with metadata at the top)

    @ViewBuilder
    private var summarySection: some View {
        if let summary = document.summary {
            VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                Text("Summary · Local LLM")
                    .font(Japandi.Typography.eyebrow)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Japandi.Colors.inspectorInk3)

                Text(summary)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Japandi.Colors.inspectorInk2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Preview (pinned, full-bleed, takes the rest of the inspector)

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview")
                    .font(Japandi.Typography.eyebrow)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Japandi.Colors.inspectorInk3)
                Spacer()
                Button {
                    showPreview = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Pop out")
                            .font(.system(size: 10.5))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Japandi.Colors.inspectorAccent)
                }
                .buttonStyle(.plain)
                .help("Open the document in a full-size window")
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Bleed the actual viewer edge-to-edge so it feels like a real
            // document surface inside the inspector instead of a card.
            DocumentInlinePreview(document: document)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func saveTitleEdit() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            editedTitle = document.title
            isEditing = false
            return
        }

        document.title = trimmedTitle
        document.modifiedAt = .now
        document.rebuildSearchableText()
        try? modelContext.save()
        isEditing = false
    }

    private func addTag() {
        let name = normalizeTagName(newTagName)
        guard !name.isEmpty else { return }

        let predicate = #Predicate<Tag> { $0.name == name }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let existing = try? modelContext.fetch(descriptor).first
        let tag = existing ?? Tag(name: name, colorHex: Tag.defaultColors.randomElement() ?? "2A639D")
        if existing == nil {
            modelContext.insert(tag)
        }

        if document.tags == nil { document.tags = [] }
        if !(document.tags?.contains(where: { $0.name == name }) ?? false) {
            document.tags?.append(tag)
        }
        document.rebuildSearchableText()
        try? modelContext.save()
        newTagName = ""
    }

    private func removeTag(_ tag: Tag) {
        document.tags?.removeAll { $0.name == tag.name }
        document.rebuildSearchableText()
        try? modelContext.save()
    }

    private func normalizeTagName(_ rawName: String) -> String {
        rawName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "-")
    }

}

// MARK: - Metadata Row

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.inspectorInk3)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.inspectorInk)
                .textSelection(.enabled)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
