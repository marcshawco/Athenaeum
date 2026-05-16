import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("defaultViewMode") private var defaultViewMode: String = "grid"
    @AppStorage("chunkSize") private var chunkSize = 512
    @AppStorage("chunkOverlap") private var chunkOverlap = 64
    @AppStorage("maxGPULayers") private var maxGPULayers = -1
    @AppStorage("contextSize") private var contextSize = 4096
    @State private var vaultPath = DocumentVaultService.shared.vaultURL.path
    @State private var selection: SettingsTab = .general

    var modelManager: ModelManager

    enum SettingsTab: Hashable {
        case general, ai, storage, about
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            HStack(spacing: 0) {
                sidebar
                Divider().foregroundStyle(Japandi.Colors.borderFallback)
                contentArea
            }
        }
        .frame(width: 720, height: 560)
        .background(Japandi.Colors.bgFallback)
        .onAppear {
            vaultPath = DocumentVaultService.shared.vaultURL.path
        }
    }

    // MARK: - Window chrome

    private var header: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
        }
        .padding(.horizontal, Japandi.Spacing.md)
        .frame(height: 44)
        .background(Japandi.Colors.surfaceFallback)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarRow(.general, icon: "gear",         label: "General")
            sidebarRow(.ai,      icon: "cpu",          label: "AI Models")
            sidebarRow(.storage, icon: "internaldrive",label: "Storage")
            sidebarRow(.about,   icon: "info.circle",  label: "About")
            Spacer()
        }
        .padding(.horizontal, Japandi.Spacing.xs)
        .padding(.top, Japandi.Spacing.sm)
        .frame(width: 180)
        .background(Japandi.Colors.surfaceFallback)
    }

    private func sidebarRow(_ tab: SettingsTab, icon: String, label: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: Japandi.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(isSelected
                                     ? Japandi.Colors.accentFallback
                                     : Japandi.Colors.textTertiaryFB)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12.5,
                                  weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected
                                     ? Japandi.Colors.textPrimaryFB
                                     : Japandi.Colors.textSecondaryFB)
                Spacer()
            }
            .padding(.horizontal, Japandi.Spacing.xs)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                          ? Japandi.Colors.surfaceRaisedFB
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected
                                  ? Japandi.Colors.borderFallback
                                  : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentArea: some View {
        ScrollView {
            Group {
                switch selection {
                case .general: generalTab
                case .ai:      aiTab
                case .storage: storageTab
                case .about:   aboutTab
                }
            }
            .padding(Japandi.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Japandi.Colors.bgFallback)
    }

    // MARK: - General

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.lg) {
            HStack(spacing: Japandi.Spacing.md) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Athenaeum")
                        .font(.system(size: 24, weight: .light, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("A private archive")
                        .font(.system(size: 12))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        .padding(.top, 4)
                }

                Spacer()
            }

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            Text("Local Intelligence")
                .font(Japandi.Typography.eyebrow)
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Japandi.Colors.accentFallback)

            Text("A quiet, indexed corner of your life. Everything stays on this Mac — no cloud, no tracking, no upload. The local LLM analyzes, the vector store retrieves, and the vault keeps your originals untouched.")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }

                Picker("Default View", selection: $defaultViewMode) {
                    Text("Grid").tag("grid")
                    Text("List").tag("list")
                }
            }

            Section("Import") {
                Text("Imported files and documents added to the vault are processed automatically.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.lg) {
            hardwareAnalyzerCard

            presetCard

            Form {
                Section("Inference") {
                    Picker("GPU Layers", selection: $maxGPULayers) {
                        Text("All (Recommended)").tag(-1)
                        Text("None (CPU Only)").tag(0)
                        ForEach([8, 16, 24, 32], id: \.self) { n in
                            Text("\(n) layers").tag(n)
                        }
                    }

                    Picker("Context Window", selection: $contextSize) {
                        Text("2048 tokens").tag(2048)
                        Text("4096 tokens").tag(4096)
                        Text("8192 tokens").tag(8192)
                    }

                    Text("Larger context windows use more memory but allow processing longer documents.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }

                Section("RAG Pipeline") {
                    Stepper("Chunk Size: \(chunkSize) words", value: $chunkSize, in: 128...1024, step: 128)
                    Stepper("Chunk Overlap: \(chunkOverlap) words", value: $chunkOverlap, in: 0...256, step: 32)

                    Text("Smaller chunks give more precise retrieval; larger chunks preserve more context.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
            .scrollDisabled(true)
        }
    }

    // MARK: - Hardware analyzer + presets

    @State private var analyzerResult: HardwareProfile?

    private var hardwareAnalyzerCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyze your Mac")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("Inspect cores, memory and the Metal accelerator, then pick the best defaults.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                Spacer()
                Button {
                    analyzerResult = HardwareProfile.detect()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .medium))
                        Text("Analyze")
                            .font(Japandi.Typography.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Japandi.Spacing.sm)
                    .frame(height: 26)
                    .background(Japandi.Colors.accentFallback)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let profile = analyzerResult {
                Divider().foregroundStyle(Japandi.Colors.borderFallback)

                HStack(alignment: .top, spacing: Japandi.Spacing.lg) {
                    profileStat("CPU", "\(profile.coreCount) cores")
                    profileStat("Memory", profile.memoryFormatted)
                    profileStat("Accelerator", profile.acceleratorLabel)
                    profileStat("Tier", profile.tier.label)
                }

                HStack(spacing: Japandi.Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Japandi.Colors.accentFallback)
                    Text(profile.recommendation)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    Spacer()
                    Button("Apply recommended") {
                        apply(profile.recommendedPreset)
                    }
                    .buttonStyle(.plain)
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.accentFallback)
                }
            }
        }
        .padding(Japandi.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    private func profileStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Japandi.Typography.eyebrow)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            Text("Presets")
                .font(Japandi.Typography.eyebrow)
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)

            HStack(spacing: Japandi.Spacing.sm) {
                presetButton(.everyday)
                presetButton(.powerUser)
                presetButton(.custom)
            }
        }
        .padding(Japandi.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    private func presetButton(_ preset: SettingsPreset) -> some View {
        let isActive = matchesCurrentSettings(preset) && preset != .custom
        return Button {
            apply(preset)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(isActive
                                         ? Japandi.Colors.accentFallback
                                         : Japandi.Colors.textSecondaryFB)
                    Text(preset.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Japandi.Colors.accentFallback)
                    }
                }
                Text(preset.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Japandi.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(isActive
                        ? Japandi.Colors.washFallback
                        : Japandi.Colors.bgFallback)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive
                                  ? Japandi.Colors.accentFallback
                                  : Japandi.Colors.borderFallback,
                                  lineWidth: isActive ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func apply(_ preset: SettingsPreset) {
        guard let values = preset.values else { return }
        contextSize  = values.contextSize
        maxGPULayers = values.gpuLayers
        chunkSize    = values.chunkSize
        chunkOverlap = values.chunkOverlap
    }

    private func matchesCurrentSettings(_ preset: SettingsPreset) -> Bool {
        guard let v = preset.values else { return false }
        return v.contextSize == contextSize
            && v.gpuLayers == maxGPULayers
            && v.chunkSize == chunkSize
            && v.chunkOverlap == chunkOverlap
    }

    // MARK: - Storage

    private var storageTab: some View {
        Form {
            Section("Data Location") {
                LabeledContent("Document Vault") {
                    VStack(alignment: .trailing, spacing: Japandi.Spacing.xs) {
                        Text(vaultPath)
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textSecondaryFB)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: Japandi.Spacing.xs) {
                            Button("Choose...") {
                                chooseVaultFolder()
                            }
                            Button("Reveal") {
                                DocumentVaultService.shared.revealVault()
                            }
                            Button("Scan Now") {
                                NotificationCenter.default.post(name: .scanDocumentVault, object: nil)
                            }
                        }
                        .font(Japandi.Typography.caption)
                    }
                }

                Text("This is the local super folder. Files imported through Athenaeum are copied here, and files you add in Finder are scanned and processed when the app opens.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)

                LabeledContent("Documents Database") {
                    Text(databasePath)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Model Files") {
                    HStack {
                        Text(modelManager.modelsDirectory.path)
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textSecondaryFB)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Reveal") {
                            NSWorkspace.shared.open(modelManager.modelsDirectory)
                        }
                        .font(Japandi.Typography.caption)
                    }
                }

                LabeledContent("Vector Store") {
                    Text(vectorStorePath)
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var databasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Athenaeum/default.store").path
    }

    private var vectorStorePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Athenaeum/vector_store.json").path
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Athenaeum Document Vault"
        panel.message = "Choose the local folder where Athenaeum stores and watches your documents."
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = DocumentVaultService.shared.vaultURL

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try DocumentVaultService.shared.setVaultURL(url)
            vaultPath = url.path
            NotificationCenter.default.post(name: .scanDocumentVault, object: nil)
        } catch {
            NSSound.beep()
        }
    }
}

// MARK: - Settings Presets

enum SettingsPreset: String, CaseIterable, Hashable {
    /// Conservative defaults for everyday document filing on lightweight Macs.
    case everyday
    /// Aggressive defaults for power users with high-RAM Apple silicon.
    case powerUser
    /// User-tuned values — no preset applied.
    case custom

    struct Values {
        let contextSize: Int
        let gpuLayers: Int     // -1 = all (Metal full offload), 0 = CPU-only
        let chunkSize: Int
        let chunkOverlap: Int
    }

    var title: String {
        switch self {
        case .everyday:  "Everyday"
        case .powerUser: "Power User"
        case .custom:    "Custom"
        }
    }

    var summary: String {
        switch self {
        case .everyday:  "Balanced quality. Light on memory. Good for laptops."
        case .powerUser: "Maximum context and recall. Best on 32GB+ Macs."
        case .custom:    "Tune every value yourself in the form below."
        }
    }

    var icon: String {
        switch self {
        case .everyday:  "leaf"
        case .powerUser: "bolt"
        case .custom:    "slider.horizontal.3"
        }
    }

    var values: Values? {
        switch self {
        case .everyday:
            return Values(contextSize: 4096, gpuLayers: -1, chunkSize: 512, chunkOverlap: 64)
        case .powerUser:
            return Values(contextSize: 8192, gpuLayers: -1, chunkSize: 768, chunkOverlap: 128)
        case .custom:
            return nil
        }
    }
}

// MARK: - Hardware Profile

/// Snapshot of the user's Mac used to recommend a preset.
struct HardwareProfile {
    let coreCount: Int
    let physicalMemoryBytes: UInt64
    let hasMetal: Bool

    enum Tier {
        case light, balanced, pro

        var label: String {
            switch self {
            case .light:    "Light"
            case .balanced: "Balanced"
            case .pro:      "Pro"
            }
        }
    }

    var tier: Tier {
        // ≤8 GB RAM or ≤4 cores → light
        // ≤16 GB RAM            → balanced
        // >16 GB RAM            → pro
        let gb = Double(physicalMemoryBytes) / 1_073_741_824
        if gb <= 9 || coreCount <= 4 { return .light }
        if gb <= 17 { return .balanced }
        return .pro
    }

    var recommendedPreset: SettingsPreset {
        switch tier {
        case .light, .balanced: .everyday
        case .pro:              .powerUser
        }
    }

    var memoryFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(physicalMemoryBytes), countStyle: .memory)
    }

    var acceleratorLabel: String {
        hasMetal ? "Metal" : "CPU only"
    }

    var recommendation: String {
        switch tier {
        case .light:
            return "Use Everyday — keeps context at 4K and chunks small so processing stays snappy."
        case .balanced:
            return "Use Everyday — your Mac can handle bigger context, but Everyday is best for daily use."
        case .pro:
            return "Use Power User — your Mac can run 8K context with larger chunks for better recall."
        }
    }

    static func detect() -> HardwareProfile {
        HardwareProfile(
            coreCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            // All Apple silicon and recent Intel Macs ship with Metal; we treat it as available.
            hasMetal: true
        )
    }
}

// MARK: - App Appearance

enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}
