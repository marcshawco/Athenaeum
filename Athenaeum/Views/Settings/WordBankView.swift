import SwiftUI
import SwiftData

// MARK: - Word Bank Settings
//
// User-facing CRUD for `KnowledgeEntry` rows. The settings panel teaches the
// local AI which terms refer to the same real-world entity:
//   - "Me / I / Marc" → Marcus Shaw
//   - "Kaiser" → medical insurance provider
//   - "WGU" → school
//
// Every chat turn re-reads from this list, so an edit you make here applies
// to the very next message you send.

struct WordBankView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnowledgeEntry.canonicalName) private var entries: [KnowledgeEntry]

    @State private var search: String = ""
    @State private var editing: EditTarget?
    @State private var deleteTarget: KnowledgeEntry?

    /// `.new` opens an empty editor; `.existing(_)` opens the editor pre-filled.
    private enum EditTarget: Identifiable {
        case new
        case existing(KnowledgeEntry)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let e): e.id.uuidString
            }
        }
    }

    private var filtered: [KnowledgeEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { e in
            e.canonicalName.lowercased().contains(q)
                || e.aliases.contains(where: { $0.contains(q) })
                || (e.notes ?? "").lowercased().contains(q)
                || (e.category ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            header
            searchField
            list
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { target in
            entryEditor(for: target)
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \u{201C}\($0.canonicalName)\u{201D}?" } ?? "Delete entry?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                modelContext.delete(target)
                try? modelContext.save()
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("Removes this entry from the word bank. Documents that mention it are untouched.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Word Bank")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
            Text("Teach ATHENS which names, nicknames, and abbreviations refer to the same thing. Add yourself as \u{201C}me\u{201D}, your insurance as \u{201C}Kaiser\u{201D}, your school as \u{201C}WGU\u{201D} — chat will use these to find the right documents.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            TextField("Find an entry", text: $search)
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

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        entryRow(entry)
                        Divider().foregroundStyle(Japandi.Colors.borderFallback.opacity(0.5))
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
    }

    private var emptyState: some View {
        VStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.borderFallback)
            Text("No entries yet")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
            Text("Start by adding yourself — name, nicknames, and any pronouns you use. Chat will instantly understand \u{201C}I\u{201D} and \u{201C}me\u{201D}.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Japandi.Spacing.lg)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    private func entryRow(_ entry: KnowledgeEntry) -> some View {
        Button {
            editing = .existing(entry)
        } label: {
            HStack(alignment: .top, spacing: Japandi.Spacing.sm) {
                Image(systemName: categoryIcon(entry))
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.canonicalName)
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        if entry.isSelf {
                            Text("YOU")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Japandi.Colors.accentFallback)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Japandi.Colors.washFallback)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Japandi.Colors.accentFallback.opacity(0.35), lineWidth: 0.5))
                        }
                        if let cat = entry.category {
                            Text(cat.uppercased())
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                    }
                    if !entry.aliases.isEmpty {
                        Text("aka " + entry.aliases.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(Japandi.Colors.textSecondaryFB)
                            .lineLimit(1)
                    }
                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)

                Button {
                    deleteTarget = entry
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Japandi.Colors.warmFallback)
                }
                .buttonStyle(.plain)
                .help("Delete entry")
                .accessibilityLabel("Delete \(entry.canonicalName)")
            }
            .padding(.horizontal, Japandi.Spacing.sm)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ entry: KnowledgeEntry) -> String {
        guard let raw = entry.category, let cat = KnowledgeCategory(rawValue: raw) else {
            return "tag"
        }
        return cat.iconName
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                editing = .new
            } label: {
                Label("Add entry…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Japandi.Colors.accentFallback)
            Spacer()
            if !entries.isEmpty {
                Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
    }

    // MARK: - Editor sheet

    @ViewBuilder
    private func entryEditor(for target: EditTarget) -> some View {
        switch target {
        case .new:
            WordBankEntryEditor(entry: nil) { saved in
                modelContext.insert(saved)
                if saved.isSelf {
                    for other in entries where other.id != saved.id && other.isSelf {
                        other.isSelf = false
                    }
                }
                try? modelContext.save()
                editing = nil
            } onCancel: {
                editing = nil
            }

        case .existing(let entry):
            WordBankEntryEditor(entry: entry) { saved in
                // Same instance; SwiftData picks up the mutations.
                if saved.isSelf {
                    for other in entries where other.id != saved.id && other.isSelf {
                        other.isSelf = false
                    }
                }
                try? modelContext.save()
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }
}

// MARK: - Editor sheet

/// Standalone editor used for both "new" and "edit". When `entry` is nil we
/// construct a fresh model and pass it back to the parent in `onSave`,
/// which is responsible for inserting it into the context.
private struct WordBankEntryEditor: View {
    let entry: KnowledgeEntry?
    let onSave: (KnowledgeEntry) -> Void
    let onCancel: () -> Void

    @State private var canonicalName: String = ""
    @State private var aliases: [String] = []
    @State private var newAliasText: String = ""
    @State private var notes: String = ""
    @State private var categoryRaw: String = ""
    @State private var isSelf: Bool = false

    private var isValid: Bool {
        !canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            header

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Canonical name")
                TextField("Marcus Shaw, Kaiser Permanente, WGU…", text: $canonicalName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Aliases")
                aliasField
                if !aliases.isEmpty {
                    aliasChips
                }
                Text("Other names, nicknames, abbreviations, or pronouns. Press Enter or comma to add.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Category")
                Picker("Category", selection: $categoryRaw) {
                    Text("Uncategorized").tag("")
                    ForEach(KnowledgeCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Notes for the AI")
                TextField("My medical insurance provider…", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(isOn: $isSelf) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This entry is me")
                        .font(Japandi.Typography.body)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("When you say \u{201C}I\u{201D} or \u{201C}me\u{201D} in chat, ATHENS will treat it as this name.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(Japandi.Colors.accentFallback)

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add entry" : "Save changes") {
                    commit()
                }
                .buttonStyle(.borderedProminent)
                .tint(Japandi.Colors.accentFallback)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(Japandi.Spacing.lg)
        .frame(width: 420)
        .onAppear(perform: loadInitialState)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry == nil ? "New entry" : "Edit entry")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Japandi.Colors.textTertiaryFB)
    }

    private var aliasField: some View {
        TextField("Add an alias", text: $newAliasText)
            .textFieldStyle(.roundedBorder)
            .onSubmit { addAlias() }
            .onChange(of: newAliasText) { _, newValue in
                // Comma-delimited bulk add — paste a list and they explode
                // into chips immediately.
                if newValue.contains(",") {
                    let parts = newValue.split(separator: ",").map { String($0) }
                    for part in parts where !part.trimmingCharacters(in: .whitespaces).isEmpty {
                        appendAlias(part)
                    }
                    newAliasText = ""
                }
            }
    }

    private var aliasChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(aliases, id: \.self) { alias in
                HStack(spacing: 4) {
                    Text(alias)
                        .font(.system(size: 11))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Button {
                        aliases.removeAll { $0 == alias }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(alias)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Japandi.Colors.washFallback)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Japandi.Colors.accentFallback.opacity(0.25), lineWidth: 0.5))
            }
        }
    }

    // MARK: - State

    private func loadInitialState() {
        if let entry {
            canonicalName = entry.canonicalName
            aliases = entry.aliases
            notes = entry.notes ?? ""
            categoryRaw = entry.category ?? ""
            isSelf = entry.isSelf
        }
    }

    private func addAlias() {
        appendAlias(newAliasText)
        newAliasText = ""
    }

    private func appendAlias(_ raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !aliases.contains(normalized) else { return }
        aliases.append(normalized)
    }

    private func commit() {
        // Pull in anything still pending in the alias field.
        appendAlias(newAliasText)
        newAliasText = ""

        let finalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAliases = KnowledgeEntry.normalizeAliases(aliases)
        let finalCategory: String? = categoryRaw.isEmpty ? nil : categoryRaw

        if let existing = entry {
            existing.canonicalName = finalName
            existing.aliases = cleanedAliases
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.category = finalCategory
            existing.isSelf = isSelf
            existing.modifiedAt = .now
            onSave(existing)
        } else {
            let fresh = KnowledgeEntry(
                canonicalName: finalName,
                aliases: cleanedAliases,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                category: finalCategory,
                isSelf: isSelf
            )
            onSave(fresh)
        }
    }
}
