import SwiftUI
import SwiftData

// MARK: - Tag Library
//
// Settings panel for managing the tag vocabulary: rename, recolor, hide, and
// delete tags. "Hidden" tags are stored in @AppStorage as a comma-joined list
// of names; the sidebar and grid filters honor this list. Deleting actually
// removes the Tag row (and its membership in every document).

struct TagLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]
    @AppStorage("hiddenTags") private var hiddenTagsRaw: String = ""

    @State private var renameTarget: Tag?
    @State private var renameText: String = ""
    @State private var deleteTarget: Tag?
    @State private var search: String = ""

    private var hiddenSet: Set<String> {
        get { Set(hiddenTagsRaw.split(separator: ",").map { String($0) }) }
    }

    private var filteredTags: [Tag] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tags }
        return tags.filter { $0.name.contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            header
            searchField
            tagList
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $renameTarget) { tag in
            renameSheet(for: tag)
        }
        .confirmationDialog(
            deleteTarget.map { "Delete tag \u{201C}\($0.name)\u{201D}?" } ?? "Delete tag?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { tag in
            Button("Delete", role: .destructive) {
                deleteTag(tag)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { tag in
            Text("Removes the tag from \(tag.documents?.count ?? 0) document(s). This cannot be undone.")
        }
    }

    // MARK: - Header & search

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tag Library")
                    .font(.system(size: 24, weight: .light, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text("\(tags.count) tag\(tags.count == 1 ? "" : "s") · \(hiddenSet.count) hidden · \(unusedTags.count) unused")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
            Spacer()
            Button(action: clearUnusedTags) {
                Label("Clear unused", systemImage: "trash")
            }
            .font(Japandi.Typography.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(unusedTags.isEmpty)
            .help("Delete every tag that has zero attached documents")
        }
    }

    /// Tags with no attached documents — candidates for the "Clear unused" sweep.
    private var unusedTags: [Tag] {
        tags.filter { ($0.documents?.isEmpty ?? true) }
    }

    private func clearUnusedTags() {
        let targets = unusedTags
        guard !targets.isEmpty else { return }
        for tag in targets {
            modelContext.delete(tag)
        }
        modelContext.persist(context: "tag-library-prune-unused")
        NotificationCenter.default.post(name: .tagsDidChange, object: nil)
    }

    private var searchField: some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            TextField("Find a tag", text: $search)
                .textFieldStyle(.plain)
                .font(Japandi.Typography.body)
        }
        .padding(.horizontal, Japandi.Spacing.sm)
        .padding(.vertical, 6)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    // MARK: - List

    private var tagList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredTags) { tag in
                    tagRow(tag)
                    Divider().foregroundStyle(Japandi.Colors.borderFallback)
                }
            }
        }
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isHidden = hiddenSet.contains(tag.name)
        return HStack(spacing: Japandi.Spacing.sm) {
            Circle()
                .fill(Color(hex: UInt(tag.colorHex, radix: 16) ?? 0x3E5C4A))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(tag.name)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(isHidden
                                     ? Japandi.Colors.textTertiaryFB
                                     : Japandi.Colors.textPrimaryFB)
                    .strikethrough(isHidden, color: Japandi.Colors.textTertiaryFB)
                Text("\(tag.documents?.count ?? 0) doc\((tag.documents?.count ?? 0) == 1 ? "" : "s")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            Spacer()

            Button {
                toggleHidden(tag)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            }
            .buttonStyle(.plain)
            .help(isHidden ? "Show in sidebar" : "Hide from sidebar")
            .accessibilityLabel(isHidden ? "Show tag" : "Hide tag")

            Button {
                renameText = tag.name
                renameTarget = tag
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            }
            .buttonStyle(.plain)
            .help("Rename tag")
            .accessibilityLabel("Rename tag")

            Button {
                deleteTarget = tag
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.warmFallback)
            }
            .buttonStyle(.plain)
            .help("Delete tag")
            .accessibilityLabel("Delete tag")
        }
        .padding(.horizontal, Japandi.Spacing.sm)
        .padding(.vertical, 8)
    }

    // MARK: - Rename sheet

    private func renameSheet(for tag: Tag) -> some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            Text("Rename tag")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
            TextField("New name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(for: tag) }
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                Button("Save") { commitRename(for: tag) }
                    .buttonStyle(.borderedProminent)
                    .tint(Japandi.Colors.accentFallback)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Japandi.Spacing.lg)
        .frame(width: 340)
    }

    // MARK: - Mutations

    private func toggleHidden(_ tag: Tag) {
        var set = hiddenSet
        if set.contains(tag.name) {
            set.remove(tag.name)
        } else {
            set.insert(tag.name)
        }
        hiddenTagsRaw = set.sorted().joined(separator: ",")
        NotificationCenter.default.post(name: .tagsDidChange, object: nil)
    }

    private func commitRename(for tag: Tag) {
        let new = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        guard !new.isEmpty, new != tag.name else { renameTarget = nil; return }

        // If a tag with the target name already exists, merge into it.
        let predicate = #Predicate<Tag> { $0.name == new }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        if let merged = try? modelContext.fetch(descriptor).first, merged !== tag {
            // Move all docs onto the target tag, then delete the source.
            for doc in tag.documents ?? [] {
                if !(merged.documents?.contains(doc) ?? false) {
                    merged.documents = (merged.documents ?? []) + [doc]
                }
            }
            modelContext.delete(tag)
        } else {
            tag.name = new
        }
        modelContext.persist(context: "tag-library-rename")
        renameTarget = nil
        NotificationCenter.default.post(name: .tagsDidChange, object: nil)
    }

    private func deleteTag(_ tag: Tag) {
        // Remove the tag entirely; SwiftData detaches it from documents.
        modelContext.delete(tag)
        modelContext.persist(context: "tag-library-delete")
        NotificationCenter.default.post(name: .tagsDidChange, object: nil)
    }
}
