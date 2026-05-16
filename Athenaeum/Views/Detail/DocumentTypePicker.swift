import SwiftUI

// MARK: - Document Type Picker
//
// Searchable picker over the canonical 500-type taxonomy. Used from the
// document inspector to accept or correct the local LLM's classification.
//
// Closure-based callbacks (rather than a Binding) so this can sit cleanly
// over a SwiftData @Bindable document without conflicting with the host's
// modelContext save lifecycle.

struct DocumentTypePicker: View {
    let currentSlug: String?
    var onSelect: (DocumentTaxonomy.DocumentType?) -> Void
    var onCancel: () -> Void

    @State private var query: String = ""
    @State private var selectedSlug: String?

    init(
        currentSlug: String?,
        onSelect: @escaping (DocumentTaxonomy.DocumentType?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.currentSlug = currentSlug
        self.onSelect = onSelect
        self.onCancel = onCancel
        self._selectedSlug = State(initialValue: currentSlug)
    }

    /// Flat (type, category) pairs filtered by the search term. Search is
    /// case-insensitive against both the type name and the parent category
    /// so a query like "lease" matches the Real Estate category too.
    private var matches: [(type: DocumentTaxonomy.DocumentType, category: DocumentTaxonomy.Category)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows: [(DocumentTaxonomy.DocumentType, DocumentTaxonomy.Category)] = []
        for cat in DocumentTaxonomy.categories {
            for type in cat.types {
                if q.isEmpty
                    || type.name.lowercased().contains(q)
                    || type.purpose.lowercased().contains(q)
                    || cat.name.lowercased().contains(q) {
                    rows.append((type, cat))
                }
            }
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(Japandi.Colors.borderFallback)
            searchField
            list
            Divider().foregroundStyle(Japandi.Colors.borderFallback)
            footer
        }
        .frame(width: 560, height: 560)
        .background(Japandi.Colors.bgFallback)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Document Type")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text("\(DocumentTaxonomy.allTypes.count) types across \(DocumentTaxonomy.categories.count) categories")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
            Spacer()
            Button { onCancel() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close picker")
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, Japandi.Spacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            TextField("Search by type, purpose, or category", text: $query)
                .textFieldStyle(.plain)
                .font(Japandi.Typography.body)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(matches, id: \.type.slug) { row in
                    pickerRow(type: row.type, category: row.category)
                    Divider().foregroundStyle(Japandi.Colors.borderFallback.opacity(0.6))
                }
            }
        }
    }

    private func pickerRow(type: DocumentTaxonomy.DocumentType, category: DocumentTaxonomy.Category) -> some View {
        let isSelected = selectedSlug == type.slug
        return Button {
            selectedSlug = type.slug
        } label: {
            HStack(alignment: .top, spacing: Japandi.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.name)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text(type.purpose)
                        .font(.system(size: 11))
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .lineLimit(2)
                    Text(category.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Japandi.Colors.accentMutedFallback)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Japandi.Colors.accentFallback)
                }
            }
            .padding(.horizontal, Japandi.Spacing.md)
            .padding(.vertical, 8)
            .background(isSelected ? Japandi.Colors.washFallback : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Button("Clear type") {
                onSelect(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Japandi.Colors.warmFallback)
            .disabled(currentSlug == nil)
            Spacer()
            Button("Cancel") { onCancel() }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
            Button("Save") {
                if let slug = selectedSlug,
                   let type = DocumentTaxonomy.type(forSlug: slug) {
                    onSelect(type)
                } else {
                    onSelect(nil)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Japandi.Colors.accentFallback)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedSlug == nil)
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .padding(.vertical, Japandi.Spacing.sm)
    }
}
