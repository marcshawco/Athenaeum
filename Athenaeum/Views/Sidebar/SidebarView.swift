import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var allDocuments: [Document]
    @Binding var selectedTag: String?
    @Binding var selectedSection: SidebarSection
    @AppStorage("hiddenTags") private var hiddenTagsRaw: String = ""

    private var visibleTags: [Tag] {
        let hidden = Set(hiddenTagsRaw.split(separator: ",").map { String($0) })
        return tags.filter { !hidden.contains($0.name) }
    }

    /// Categories from `DocumentTaxonomy` that currently have at least one
    /// document. Sorted by descending document count so the user's busiest
    /// shelves float to the top.
    private var categoriesWithDocs: [DocumentTaxonomy.Category] {
        var counts: [String: Int] = [:]
        for doc in allDocuments {
            if let slug = doc.categorySlug { counts[slug, default: 0] += 1 }
        }
        return DocumentTaxonomy.categories
            .filter { counts[$0.slug, default: 0] > 0 }
            .sorted { (counts[$0.slug] ?? 0) > (counts[$1.slug] ?? 0) }
    }

    private func documentsInCategory(_ slug: String) -> [Document] {
        allDocuments.filter { $0.categorySlug == slug }
    }

    /// Trim the noisy " Documents" suffix the taxonomy uses for readability
    /// in a narrow sidebar.
    private func shortCategoryName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " Documents", with: "")
            .replacingOccurrences(of: " & ", with: " · ")
    }

    private func iconForCategory(_ slug: String) -> String {
        switch slug {
        case "personal-identity-documents":           "person.text.rectangle"
        case "academic-educational-documents":        "graduationcap"
        case "legal-documents-contracts-agreements":  "doc.text.below.ecg"
        case "legal-documents-instruments-court-filings": "scalemass"
        case "business-corporate-documents":          "building.2"
        case "human-resources-documents":             "person.3"
        case "financial-accounting-documents":        "dollarsign.circle"
        case "real-estate-property-documents":        "house"
        case "insurance-documents":                   "shield.lefthalf.filled"
        case "government-regulatory-documents":       "building.columns"
        case "medical-healthcare-documents":          "cross.case"
        case "shipping-logistics-trade-documents":    "shippingbox"
        case "technical-engineering-documents":       "gearshape.2"
        case "software-it-documents":                 "terminal"
        case "research-scientific-documents":         "atom"
        case "marketing-sales-communications-documents": "megaphone"
        case "financial-securities-investment-documents": "chart.line.uptrend.xyaxis"
        case "nonprofit-governance-compliance-documents": "checkmark.shield"
        case "diplomatic-military-intelligence-documents": "globe"
        case "specialized-miscellaneous-document-types":  "rectangle.3.group"
        default: "folder"
        }
    }

    private var pendingCount: Int {
        allDocuments.filter { $0.processingStatus == .pending || $0.processingStatus == .extractingText || $0.processingStatus == .analyzingContent || $0.processingStatus == .tagging }.count
    }

    private var untaggedCount: Int {
        allDocuments.filter { $0.tags == nil || $0.tags?.isEmpty == true }.count
    }

    private var recentDocuments: [Document] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return allDocuments.filter { $0.importedAt >= cutoff }
    }

    var body: some View {
        List(selection: $selectedSection) {
            // MARK: - Library
            Section {
                sidebarRow(
                    "All Documents",
                    icon: "doc.on.doc",
                    tag: .all,
                    count: allDocuments.count
                )

                sidebarRow(
                    "Recent",
                    icon: "clock",
                    tag: .recent,
                    count: recentDocuments.count
                )

                if pendingCount > 0 {
                    sidebarRow(
                        "Processing",
                        icon: "gearshape.2",
                        tag: .processing,
                        count: pendingCount,
                        accentColor: Japandi.Colors.accentMutedFallback
                    )
                }

                sidebarRow(
                    "Untagged",
                    icon: "tag.slash",
                    tag: .untagged,
                    count: untaggedCount
                )
            } header: {
                Text("Library")
                    .eyebrowStyle()
            }

            // MARK: - Tags
            if !visibleTags.isEmpty {
                Section {
                    ForEach(visibleTags) { tag in
                        HStack(spacing: Japandi.Spacing.xs) {
                            Circle()
                                .fill(Color(hex: UInt(tag.colorHex, radix: 16) ?? 0x2A639D))
                                .frame(width: 6, height: 6)

                            Text(tag.name.capitalized)
                                .font(Japandi.Typography.body)
                                .foregroundStyle(Japandi.Colors.textPrimaryFB)

                            Spacer()

                            Text("\(tag.documents?.count ?? 0)")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Japandi.Colors.surfaceFallback)
                                .clipShape(Capsule())
                        }
                        .tag(SidebarSection.tag(tag.name))
                        .contentShape(Rectangle())
                    }
                } header: {
                    HStack {
                        Text("Tags")
                            .eyebrowStyle()
                        Spacer()
                        Text("\(tags.count)")
                            .font(Japandi.Typography.eyebrow)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                }
            }

            // MARK: - By Category (taxonomy)
            if !categoriesWithDocs.isEmpty {
                Section {
                    ForEach(categoriesWithDocs, id: \.slug) { (cat) in
                        HStack(spacing: Japandi.Spacing.xs) {
                            Image(systemName: iconForCategory(cat.slug))
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(Japandi.Colors.accentMutedFallback)
                                .frame(width: 14)
                            Text(shortCategoryName(cat.name))
                                .font(Japandi.Typography.body)
                                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                                .lineLimit(1)
                            Spacer()
                            Text("\(documentsInCategory(cat.slug).count)")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Japandi.Colors.surfaceFallback)
                                .clipShape(Capsule())
                        }
                        .tag(SidebarSection.category(cat.slug))
                        .contentShape(Rectangle())
                    }
                } header: {
                    HStack {
                        Text("By Category")
                            .eyebrowStyle()
                        Spacer()
                        Text("\(categoriesWithDocs.count)")
                            .font(Japandi.Typography.eyebrow)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                }
            }

            // MARK: - AI
            Section {
                Label {
                    Text("Document Chat")
                        .font(Japandi.Typography.body)
                } icon: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundStyle(Japandi.Colors.accentFallback)
                        .font(.system(size: 12, weight: .light))
                }
                .tag(SidebarSection.chat)

                Label {
                    Text("Model Status")
                        .font(Japandi.Typography.body)
                } icon: {
                    Image(systemName: "cpu")
                        .foregroundStyle(Japandi.Colors.accentMutedFallback)
                        .font(.system(size: 12, weight: .light))
                }
                .tag(SidebarSection.models)
            } header: {
                Text("AI")
                    .eyebrowStyle()
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(Japandi.Colors.accentFallback)
        .background(Japandi.Colors.bgFallback)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Japandi.Spacing.sm) {
                    Image("BrandMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Athenaeum")
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Japandi.Colors.textPrimaryFB)

                        Text("Private archive")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }

                    Spacer()

                    Button {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                    .accessibilityLabel("Open Settings")
                }
                .padding(.horizontal, Japandi.Spacing.md)
                .padding(.top, Japandi.Spacing.md)
                .padding(.bottom, Japandi.Spacing.md)

                Rectangle()
                    .fill(Japandi.Colors.borderFallback.opacity(0.8))
                    .frame(height: 0.5)
            }
            .background(Japandi.Colors.bgFallback)
        }
    }

    // MARK: - Sidebar Row Helper

    private func sidebarRow(
        _ title: String,
        icon: String,
        tag: SidebarSection,
        count: Int,
        accentColor: Color = Japandi.Colors.textSecondaryFB
    ) -> some View {
        Label {
            HStack {
                Text(title)
                    .font(Japandi.Typography.body)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Japandi.Colors.surfaceFallback)
                        .clipShape(Capsule())
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(accentColor)
                .font(.system(size: 12, weight: .light))
        }
        .tag(tag)
        .padding(.vertical, 1)
    }
}

// MARK: - Sidebar Section

enum SidebarSection: Hashable, Sendable {
    case all
    case recent
    case processing
    case untagged
    case tag(String)
    /// Filter by a taxonomy category slug (e.g. `real-estate-property-documents`).
    case category(String)
    case chat
    case models
}
