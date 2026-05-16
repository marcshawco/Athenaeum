import SwiftUI

struct ModelStatusView: View {
    var modelManager: ModelManager
    var modelDownloader: ModelDownloader
    var llmService: LocalLLMService? = nil

    /// Confirmation state for destructive uninstall actions.
    @State private var uninstallTarget: LLMModelDescriptor?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Japandi.Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                    Text("On-Device Models")
                        .eyebrowStyle(Japandi.Colors.accentFallback)

                    Text("Local AI")
                        .font(Japandi.Typography.largeTitle)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)

                    Text("Three specialised models running entirely on your Mac.")
                        .font(Japandi.Typography.body)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                }

                // System info
                systemInfoCard

                // Models directory
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Models directory")
                            .eyebrowStyle()
                        Text(modelManager.modelsDirectory.path)
                            .font(Japandi.Typography.mono)
                            .foregroundStyle(Japandi.Colors.textSecondaryFB)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(modelManager.modelsDirectory)
                    }
                    .font(Japandi.Typography.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Japandi.Colors.accentFallback)
                }
                .padding(Japandi.Spacing.md)
                .premiumPane()

                // Model cards
                ForEach(LLMModelDescriptor.defaults, id: \.role) { descriptor in
                    let isAvailable = modelManager.availableModels[descriptor.role] != nil
                    let isLoaded = modelManager.loadedModels.contains(descriptor.role)
                    let downloadState = modelDownloader.downloads[descriptor.role]
                    let fileSize = modelManager.modelFileSizes[descriptor.role]

                    ModelCard(
                        descriptor: descriptor,
                        isAvailable: isAvailable,
                        isLoaded: isLoaded,
                        fileSize: fileSize,
                        downloadState: downloadState,
                        onDownload: { modelDownloader.startDownload(for: descriptor.role) },
                        onCancel: { modelDownloader.cancelDownload(for: descriptor.role) },
                        onPause: { modelDownloader.pauseDownload(for: descriptor.role) },
                        onResume: { modelDownloader.resumeDownload(for: descriptor.role) },
                        onReveal: { revealModelFile(descriptor) },
                        onUninstall: { uninstallTarget = descriptor },
                        onReinstall: { reinstall(descriptor) }
                    )
                }

                // Instructions
                instructionsCard
            }
            .padding(Japandi.Spacing.lg)
        }
        .background(Japandi.Colors.bgFallback)
        .onAppear { modelManager.scanForModels() }
        .onReceive(NotificationCenter.default.publisher(for: .modelsDidChange)) { _ in
            modelManager.scanForModels()
        }
        .confirmationDialog(
            uninstallTarget.map { "Uninstall \($0.displayName)?" } ?? "Uninstall model?",
            isPresented: Binding(
                get: { uninstallTarget != nil },
                set: { if !$0 { uninstallTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: uninstallTarget
        ) { descriptor in
            Button("Uninstall", role: .destructive) {
                performUninstall(descriptor)
            }
            Button("Cancel", role: .cancel) { uninstallTarget = nil }
        } message: { descriptor in
            Text("This will delete the GGUF file from your Mac. You can re-download it at any time.\n\nFile: \(descriptor.filename)")
        }
    }

    // MARK: - Uninstall / Reinstall

    private func performUninstall(_ descriptor: LLMModelDescriptor) {
        Task {
            // 1. Unload from memory first so the file is closed.
            if let llmService, modelManager.loadedModels.contains(descriptor.role) {
                await llmService.unloadModel(descriptor.role)
            }
            // 2. Cancel any in-flight download.
            modelDownloader.cancelDownload(for: descriptor.role)
            // 3. Delete the file on disk.
            _ = await MainActor.run { modelManager.uninstallModel(descriptor) }
            uninstallTarget = nil
        }
    }

    private func reinstall(_ descriptor: LLMModelDescriptor) {
        Task {
            if let llmService, modelManager.loadedModels.contains(descriptor.role) {
                await llmService.unloadModel(descriptor.role)
            }
            modelDownloader.cancelDownload(for: descriptor.role)
            _ = await MainActor.run { modelManager.uninstallModel(descriptor) }
            await MainActor.run {
                modelDownloader.startDownload(for: descriptor.role)
            }
        }
    }

    private func revealModelFile(_ descriptor: LLMModelDescriptor) {
        let url = modelManager.modelPath(for: descriptor)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(modelManager.modelsDirectory)
        }
    }

    // MARK: - System Info

    private var systemInfoCard: some View {
        HStack(spacing: Japandi.Spacing.lg) {
            SystemStat(
                icon: "cpu",
                label: "CPU Cores",
                value: "\(ProcessInfo.processInfo.processorCount)"
            )
            SystemStat(
                icon: "memorychip",
                label: "RAM",
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory),
                    countStyle: .memory
                )
            )
            SystemStat(
                icon: "gpu",
                label: "Accelerator",
                value: "Metal"
            )
        }
        .padding(Japandi.Spacing.md)
        .frame(maxWidth: .infinity)
        .premiumPane()
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            Text("Setup")
                .font(Japandi.Typography.headline)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            Text("Click \"Download\" on any model above, or manually place GGUF files in the models directory.")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)

            VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                InstructionRow(step: "1", text: "Download quantised GGUF models (Q4_K_M recommended)")
                InstructionRow(step: "2", text: "Models load automatically when processing begins")
                InstructionRow(step: "3", text: "GPU offloading via Metal is enabled by default")
            }

            HStack(spacing: Japandi.Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                Text("Requires ~14 GB free disk space for all three models")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
        .padding(Japandi.Spacing.md)
        .premiumPane()
    }
}

// MARK: - System Stat

struct SystemStat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.accentMutedFallback)

            Text(value)
                .font(Japandi.Typography.headline)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            Text(label)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Model Card

struct ModelCard: View {
    let descriptor: LLMModelDescriptor
    let isAvailable: Bool
    let isLoaded: Bool
    var fileSize: Int64? = nil
    let downloadState: ModelDownloader.DownloadState?
    var onDownload: () -> Void = {}
    var onCancel: () -> Void = {}
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onReveal: () -> Void = {}
    var onUninstall: () -> Void = {}
    var onReinstall: () -> Void = {}

    var body: some View {
        VStack(spacing: Japandi.Spacing.sm) {
            HStack(spacing: Japandi.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                        .fill(iconColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                                .strokeBorder(iconColor.opacity(0.15), lineWidth: 0.5)
                        )
                        .frame(width: 42, height: 42)

                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .ultraLight))
                        .foregroundStyle(iconColor)
                }

                // Info
                VStack(alignment: .leading, spacing: Japandi.Spacing.xxxs) {
                    Text(descriptor.displayName)
                        .font(Japandi.Typography.headline)
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)

                    Text(roleDescription)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)

                    HStack(spacing: Japandi.Spacing.xs) {
                        MetadataBadge(text: descriptor.parameterSize)
                        MetadataBadge(text: descriptor.quantization)
                        if let fileSize {
                            MetadataBadge(text: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        }
                    }
                }

                Spacer()

                // Status + Actions
                VStack(alignment: .trailing, spacing: Japandi.Spacing.xs) {
                    statusIndicator

                    HStack(spacing: Japandi.Spacing.xs) {
                        if !isAvailable && canStartDownload {
                            Button("Download") { onDownload() }
                                .font(Japandi.Typography.caption)
                                .buttonStyle(.borderedProminent)
                                .tint(Japandi.Colors.accentFallback)
                                .controlSize(.small)
                        }

                        if isAvailable {
                            Menu {
                                Button {
                                    onReveal()
                                } label: {
                                    Label("Reveal in Finder", systemImage: "folder")
                                }
                                Button {
                                    onReinstall()
                                } label: {
                                    Label("Reinstall", systemImage: "arrow.clockwise")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    onUninstall()
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                }
            }

            // Download progress
            if let state = downloadState, state.status == .downloading || state.status == .paused {
                VStack(spacing: Japandi.Spacing.xxs) {
                    ProgressView(value: state.progress)
                        .tint(Japandi.Colors.accentFallback)

                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: state.bytesWritten, countStyle: .file))
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)

                        Spacer()

                        Text(state.speed)
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)

                        Spacer()

                        HStack(spacing: Japandi.Spacing.sm) {
                            if state.status == .downloading {
                                Button(action: onPause) {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                            } else {
                                Button(action: onResume) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Japandi.Colors.accentFallback)
                            }

                            Button(action: onCancel) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                    }
                }
            }
        }
        .padding(Japandi.Spacing.md)
        .japandiCard()
    }

    private var statusIndicator: some View {
        HStack(spacing: Japandi.Spacing.xxs) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
    }

    private var statusColor: Color {
        if isLoaded { return Japandi.Colors.accentFallback }
        if isAvailable { return Japandi.Colors.accentMutedFallback }
        if downloadState?.status == .downloading || downloadState?.status == .paused {
            return Japandi.Colors.borderFallback
        }
        if downloadState?.status == .failed { return Japandi.Colors.lacquerFallback }
        return Japandi.Colors.borderFallback
    }

    private var canStartDownload: Bool {
        guard let status = downloadState?.status else { return true }
        switch status {
        case .idle, .failed:
            return true
        case .completed:
            return !isAvailable
        case .downloading, .paused, .verifying:
            return false
        }
    }

    private var statusLabel: String {
        if isLoaded { return "Active" }
        if isAvailable { return "Ready" }
        if let state = downloadState {
            switch state.status {
            case .downloading: return "\(Int(state.progress * 100))%"
            case .paused:      return "Paused"
            case .completed:   return "Complete"
            case .failed:      return "Failed"
            case .verifying:   return "Verifying"
            default: break
            }
        }
        return "Not installed"
    }

    private var iconName: String {
        switch descriptor.role {
        case .tagger: "tag"
        case .chat:   "bubble.left.and.text.bubble.right"
        case .vision: "eye"
        }
    }

    private var iconColor: Color {
        switch descriptor.role {
        case .tagger: Japandi.Colors.accentFallback
        case .chat:   Japandi.Colors.accentMutedFallback
        case .vision: Japandi.Colors.mineralFallback
        }
    }

    private var roleDescription: String {
        switch descriptor.role {
        case .tagger: "Document classification & JSON tag extraction"
        case .chat:   "RAG-powered document Q&A"
        case .vision: "Smart OCR for images & scanned documents"
        }
    }
}

// MARK: - Metadata Badge

struct MetadataBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Japandi.Typography.caption)
            .foregroundStyle(Japandi.Colors.textTertiaryFB)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Japandi.Colors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                    .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
            )
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    let step: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Japandi.Spacing.sm) {
            Text(step)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .frame(width: 20, height: 20)
                .background(Japandi.Colors.accentFallback.opacity(0.12))
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Japandi.Colors.accentFallback.opacity(0.25), lineWidth: 0.5)
                )

            Text(text)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
        }
    }
}
