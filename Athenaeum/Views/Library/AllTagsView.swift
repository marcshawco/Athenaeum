import SwiftUI
import SwiftData

// MARK: - All Tags
//
// Dedicated browser for the full Tag vocabulary. The sidebar used to
// list every Tag row — fine at 5 tags, miserable at 50. Now the sidebar
// only shows what the user pins (cap 10) and this view is where they go
// to browse, search, and pin/unpin everything else.
//
// Clicking a tag row navigates the library to that tag's filter view
// (same as clicking a pinned tag in the sidebar). Right-click any row
// to pin/unpin from the sidebar.

struct AllTagsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Binding var selectedSection: SidebarSection
    @AppStorage("pinnedTags") private var pinnedTagsRaw: String = ""
    @AppStorage("hiddenTags") private var hiddenTagsRaw: String = ""

    @State private var search: String = ""

    private var pinnedSet: Set<String> {
        Set(pinnedTagsRaw.split(separator: ",").map { String($0) })
    }

    private var hiddenSet: Set<String> {
        Set(hiddenTagsRaw.split(separator: ",").map { String($0) })
    }

    private var visibleTags: [Tag] {
        tags.filter { !hiddenSet.contains($0.name) }
    }

    private var filteredTags: [Tag] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return visibleTags }
        return visibleTags.filter { $0.name.lowercased().contains(q) }
    }

    /// Group tags by first letter for an A–Z scannable layout, like a
    /// macOS Finder column or Eagle's tag browser.
    private var grouped: [(String, [Tag])] {
        let groups = Dictionary(grouping: filteredTags) { tag -> String in
            String(tag.name.first ?? "#").uppercased()
        }
        return groups.keys.sorted().map { key in (key, groups[key] ?? []) }
    }

    private var pinCap: Int { SidebarView.pinnedTagsCap }
    private var atPinCap: Bool { pinnedSet.count >= pinCap }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(Japandi.Colors.borderFallback)
            tagsScroller
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Japandi.Colors.surfaceFallback)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TAGS")
                        .eyebrowStyle()
                    Text("All Tags")
                        .font(Japandi.Typography.largeTitle)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("\(visibleTags.count) tag\(visibleTags.count == 1 ? "" : "s") · \(pinnedSet.count) pinned of \(pinCap) max")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                Spacer()
            }

            searchField
        }
        .padding(Japandi.Spacing.lg)
    }

    private var searchField: some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            TextField("Search tags", text: $search)
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
        .frame(maxWidth: 360)
    }

    // MARK: - Tags

    private var tagsScroller: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped, id: \.0) { (letter, list) in
                        section(letter: letter, list: list)
                    }
                }
            }
            .padding(Japandi.Spacing.lg)
        }
    }

    private func section(letter: String, list: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
            Text(letter)
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .padding(.top, Japandi.Spacing.md)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: Japandi.Spacing.sm)],
                alignment: .leading,
                spacing: Japandi.Spacing.xs
            ) {
                ForEach(list) { tag in
                    tagRow(tag)
                }
            }
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isPinned = pinnedSet.contains(tag.name)
        return Button {
            selectedSection = .tag(tag.name)
        } label: {
            HStack(spacing: Japandi.Spacing.xs) {
                Circle()
                    .fill(Color(hex: UInt(tag.colorHex, radix: 16) ?? 0x2A639D))
                    .frame(width: 8, height: 8)
                Text(tag.name.capitalized)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Japandi.Colors.accentFallback)
                }
                Spacer()
                Text("\(tag.documents?.count ?? 0)")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Japandi.Colors.surfaceRaisedFB)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Japandi.Spacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Japandi.Colors.surfaceRaisedFB.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Japandi.Colors.borderFallback.opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isPinned {
                Button {
                    unpin(tag.name)
                } label: {
                    Label("Unpin from sidebar", systemImage: "pin.slash")
                }
            } else {
                Button {
                    pin(tag.name)
                } label: {
                    Label("Pin to sidebar", systemImage: "pin")
                }
                .disabled(atPinCap)
                if atPinCap {
                    Text("Sidebar pin limit reached (\(pinCap))")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Japandi.Spacing.sm) {
            Image(systemName: "tag")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            Text(search.isEmpty ? "No tags yet" : "No tags match \u{201C}\(search)\u{201D}")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
            if search.isEmpty {
                Text("Tags appear here once you import or Auto-Tag a document.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Japandi.Spacing.xxl)
    }

    // MARK: - Pin / unpin

    private func pin(_ name: String) {
        var current = pinnedTagsRaw.split(separator: ",").map { String($0) }
        guard !current.contains(name) else { return }
        guard current.count < pinCap else { return }
        current.append(name)
        pinnedTagsRaw = current.joined(separator: ",")
    }

    private func unpin(_ name: String) {
        let current = pinnedTagsRaw.split(separator: ",").map { String($0) }
        pinnedTagsRaw = current.filter { $0 != name }.joined(separator: ",")
    }
}
