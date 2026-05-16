import SwiftUI
import SwiftData

struct FilterBarView: View {
    @Bindable var searchService: SearchService
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var showDatePicker = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate = Date.now

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Japandi.Spacing.xs) {
                // Active tag filters
                ForEach(Array(searchService.selectedTags), id: \.self) { tagName in
                    if let tag = allTags.first(where: { $0.name == tagName }) {
                        TagPillView(
                            name: tag.name,
                            colorHex: tag.colorHex,
                            isSelected: true,
                            onTap: { toggleTag(tagName) },
                            onRemove: { toggleTag(tagName) }
                        )
                    }
                }

                // Tag filter button
                Menu {
                    ForEach(allTags) { tag in
                        Button {
                            toggleTag(tag.name)
                        } label: {
                            HStack {
                                Text(tag.name.capitalized)
                                if searchService.selectedTags.contains(tag.name) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        icon: "tag",
                        label: "Tags",
                        isActive: false
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Date filter
                Button {
                    showDatePicker.toggle()
                } label: {
                    filterChip(
                        icon: "calendar",
                        label: searchService.dateRange != nil ? "Date ✓" : "Date",
                        isActive: searchService.dateRange != nil
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePicker) {
                    datePickerPopover
                }

                // Sort indicator
                Menu {
                    ForEach(SearchService.SortOrder.allCases, id: \.self) { order in
                        Button {
                            searchService.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if searchService.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(icon: "arrow.up.arrow.down", label: searchService.sortOrder.rawValue, isActive: false)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Clear all
                if !searchService.selectedTags.isEmpty || searchService.dateRange != nil {
                    Button {
                        withAnimation(Japandi.Motion.snappy) {
                            searchService.selectedTags.removeAll()
                            searchService.dateRange = nil
                        }
                    } label: {
                        Text("Clear")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.accentFallback)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Japandi.Spacing.lg)
            .padding(.vertical, Japandi.Spacing.xs)
        }
    }

    // Shared filter chip appearance
    @ViewBuilder
    private func filterChip(icon: String, label: String, isActive: Bool) -> some View {
        HStack(spacing: Japandi.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .regular))
            Text(label)
                .font(Japandi.Typography.caption)
        }
        .foregroundStyle(isActive ? Japandi.Colors.accentFallback : Japandi.Colors.textSecondaryFB)
        .padding(.horizontal, Japandi.Spacing.xs)
        .padding(.vertical, Japandi.Spacing.xxs + 1)
        .background(isActive ? Japandi.Colors.accentFallback.opacity(0.08) : Japandi.Colors.surfaceRaisedFB)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    isActive ? Japandi.Colors.accentFallback.opacity(0.25) : Japandi.Colors.borderFallback.opacity(0.85),
                    lineWidth: 0.5
                )
        )
    }

    private var datePickerPopover: some View {
        VStack(spacing: Japandi.Spacing.sm) {
            Text("Date Range")
                .font(Japandi.Typography.headline)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            DatePicker("From", selection: $startDate, displayedComponents: .date)
            DatePicker("To", selection: $endDate, displayedComponents: .date)

            HStack {
                Button("Clear") {
                    searchService.dateRange = nil
                    showDatePicker = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)

                Spacer()

                Button("Apply") {
                    searchService.dateRange = startDate...endDate
                    showDatePicker = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Japandi.Colors.accentFallback)
            }
        }
        .padding(Japandi.Spacing.md)
        .frame(width: 260)
        .background(Japandi.Colors.bgFallback)
    }

    private func toggleTag(_ name: String) {
        withAnimation(Japandi.Motion.snappy) {
            if searchService.selectedTags.contains(name) {
                searchService.selectedTags.remove(name)
            } else {
                searchService.selectedTags.insert(name)
            }
        }
    }
}
