import SwiftUI

struct ProcessingQueueView: View {
    var processor: DocumentProcessor
    var modelDownloader: ModelDownloader

    @State private var isExpanded = true

    var body: some View {
        if processor.isProcessing || hasActiveDownloads {
            VStack(spacing: 0) {
                // Header
                Button {
                    withAnimation(Japandi.Motion.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: Japandi.Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)

                        Text("Processing")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textSecondaryFB)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                    .padding(.horizontal, Japandi.Spacing.md)
                    .padding(.vertical, Japandi.Spacing.xs)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: Japandi.Spacing.xs) {
                        // Document processing
                        if processor.isProcessing {
                            processingItem(
                                icon: "doc.badge.gearshape",
                                title: processor.currentFile ?? "Processing...",
                                subtitle: "Importing & analysing",
                                progress: nil
                            )

                            if !processor.processingQueue.isEmpty {
                                Text("\(processor.processingQueue.count) more in queue")
                                    .font(Japandi.Typography.caption)
                                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Japandi.Spacing.md)
                            }
                        }

                        // Model downloads
                        ForEach(LLMRole.allCases, id: \.self) { role in
                            if let state = modelDownloader.downloads[role],
                               state.status == .downloading || state.status == .paused {
                                downloadItem(role: role, state: state)
                            }
                        }
                    }
                    .padding(.bottom, Japandi.Spacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Rectangle()
                    .fill(Japandi.Colors.borderFallback.opacity(0.8))
                    .frame(height: 0.5)
            }
            .background(Japandi.Colors.surfaceFallback.opacity(0.6))
        }
    }

    private var hasActiveDownloads: Bool {
        modelDownloader.downloads.values.contains { $0.status == .downloading || $0.status == .paused }
    }

    private func processingItem(icon: String, title: String, subtitle: String, progress: Double?) -> some View {
        HStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(Japandi.Colors.accentFallback)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            Spacer()

            if let progress {
                Text("\(Int(progress * 100))%")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
        .padding(.horizontal, Japandi.Spacing.md)
    }

    private func downloadItem(role: LLMRole, state: ModelDownloader.DownloadState) -> some View {
        VStack(spacing: Japandi.Spacing.xxxs) {
            HStack(spacing: Japandi.Spacing.xs) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Japandi.Colors.accentMutedFallback)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(role.rawValue.capitalized + " Model")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)

                    HStack(spacing: Japandi.Spacing.xxs) {
                        Text(ByteCountFormatter.string(fromByteCount: state.bytesWritten, countStyle: .file))
                        Text("·")
                        Text(state.speed)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }

                Spacer()

                Text("\(Int(state.progress * 100))%")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }

            ProgressView(value: state.progress)
                .tint(Japandi.Colors.accentFallback)
                .scaleEffect(y: 0.5)
        }
        .padding(.horizontal, Japandi.Spacing.md)
    }
}
