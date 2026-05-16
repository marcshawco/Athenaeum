import SwiftUI
import SwiftData

struct StatsDashboardView: View {
    @Query private var documents: [Document]
    @Query private var tags: [Tag]

    private var totalSize: Int64 {
        documents.reduce(0) { $0 + $1.fileSize }
    }

    private var processedCount: Int {
        documents.filter { $0.processingStatus == .complete }.count
    }

    private var pendingCount: Int {
        documents.filter { $0.processingStatus != .complete && $0.processingStatus != .failed }.count
    }

    private var failedCount: Int {
        documents.filter { $0.processingStatus == .failed }.count
    }

    private var documentsThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return documents.filter { $0.importedAt >= cutoff }.count
    }

    private var typeBreakdown: [(type: String, count: Int)] {
        var counts: [String: Int] = [:]
        for doc in documents {
            let ext = doc.fileExtension.uppercased()
            counts[ext.isEmpty ? "Other" : ext, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { (type: $0.key, count: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.lg) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                    Text("Library")
                        .eyebrowStyle(Japandi.Colors.accentFallback)

                    Text("All Documents")
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .tracking(-0.4)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)

                    Text("A quiet, indexed corner of your life. Search and ask freely — everything stays on this Mac.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                }

                Spacer()

                HStack(spacing: Japandi.Spacing.xxs) {
                    Circle()
                        .fill(Japandi.Colors.accentFallback)
                        .frame(width: 5, height: 5)
                    Text("\(processedCount) indexed")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                }
                .padding(.horizontal, Japandi.Spacing.sm)
                .padding(.vertical, Japandi.Spacing.xxs + 2)
                .background(Japandi.Colors.surfaceRaisedFB)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
                )
            }

            HStack(spacing: Japandi.Spacing.sm) {
                StatCard(
                    title: "Documents",
                    value: "\(documents.count)",
                    icon: "doc.on.doc",
                    color: Japandi.Colors.accentFallback
                )

                StatCard(
                    title: "Total Size",
                    value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                    icon: "internaldrive",
                    color: Japandi.Colors.accentMutedFallback
                )

                StatCard(
                    title: "Tags",
                    value: "\(tags.count)",
                    icon: "tag",
                    color: Japandi.Colors.mineralFallback
                )

                StatCard(
                    title: "This Week",
                    value: "\(documentsThisWeek)",
                    icon: "calendar",
                    color: Japandi.Colors.accentMutedFallback
                )
            }

            if !typeBreakdown.isEmpty {
                HStack(spacing: Japandi.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
                        Text("File Types")
                            .eyebrowStyle()

                        ForEach(typeBreakdown.prefix(5), id: \.type) { item in
                            HStack {
                                Text(item.type)
                                    .font(Japandi.Typography.mono)
                                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                                    .frame(width: 50, alignment: .leading)

                                GeometryReader { geo in
                                    let ratio = documents.isEmpty ? 0 : CGFloat(item.count) / CGFloat(documents.count)
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Japandi.Colors.accentFallback.opacity(0.22))
                                        .frame(width: geo.size.width * ratio)
                                }
                                .frame(height: 10)

                                Text("\(item.count)")
                                    .font(Japandi.Typography.caption)
                                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
                        Text("Status")
                            .eyebrowStyle()

                        StatusRow(label: "Processed", count: processedCount, color: Japandi.Colors.accentFallback)
                        StatusRow(label: "Pending", count: pendingCount, color: Japandi.Colors.accentMutedFallback)
                        if failedCount > 0 {
                            StatusRow(label: "Failed", count: failedCount, color: Japandi.Colors.lacquerFallback)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Japandi.Spacing.md)
                .premiumPane()
            }
        }
        .padding(.horizontal, Japandi.Spacing.lg)
        .padding(.top, Japandi.Spacing.lg)
        .padding(.bottom, Japandi.Spacing.md)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                    .fill(color.opacity(0.08))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(color)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .thin, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Japandi.Spacing.md)
        .premiumPane()
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 5, height: 5)

            Text(label)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)

            Spacer()

            Text("\(count)")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
        }
    }
}
