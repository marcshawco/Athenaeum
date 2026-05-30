import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Tag vocabulary feed for the priority-tag picker. Sorted by name
    /// so the picker is browseable; the picker itself filters by what
    /// the user has typed in a search field.
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("defaultViewMode") private var defaultViewMode: String = "grid"
    @AppStorage("chunkSize") private var chunkSize = 512
    @AppStorage("chunkOverlap") private var chunkOverlap = 64
    @AppStorage("maxGPULayers") private var maxGPULayers = -1
    @AppStorage("contextSize") private var contextSize = 4096
    @AppStorage("inferenceEngine") private var inferenceEngineRaw: String = InferenceEngine.llamaCpp.rawValue
    @AppStorage("autoTagEnabled") private var autoTagEnabled: Bool = true
    @AppStorage(HardwareProfiler.overrideKey) private var hardwareTierOverride: String = "auto"
    /// Persist chat conversations across app sessions. When off, the chat
    /// surface treats each visit as a fresh in-memory session and nothing
    /// is written to SwiftData.
    @AppStorage("persistChatsAcrossSessions") private var persistChatsAcrossSessions: Bool = true
    /// Low-power tagging mode. Halves the thread count used by the local
    /// LLM during auto-tag so the user's machine stays cool/quiet at the
    /// cost of slower tagging. See `LlamaInferenceConfig`.
    @AppStorage("lowPowerTagging") private var lowPowerTagging: Bool = false

    /// Free-form "about you" note. Prepended to the chat system prompt
    /// and the tagger prompt so the local LLM has a persistent sense
    /// of who the user is, their domains of interest, and any standing
    /// preferences. Empty = no injection. Read by `RAGService` and
    /// `TaggingPrompts` via `UserDefaults.standard.string(forKey:)`.
    @AppStorage("aiContextNote") private var aiContextNote: String = ""
    /// Comma-separated list of tag names the user wants prioritized
    /// during chat retrieval. When a retrieved chunk's parent document
    /// carries any of these, its score is multiplied by the boost
    /// factor in `RAGService.boostByPriorityTags` so it floats above
    /// equally-relevant chunks from unprioritized documents.
    @AppStorage("priorityTagsRaw") private var priorityTagsRaw: String = ""
    @State private var vaultPath = DocumentVaultService.shared.vaultURL.path
    @State private var selection: SettingsTab = .general
    /// First time Settings opens we land on Help & Tour instead of General, so
    /// new users see the onboarding tour without having to hunt for it.
    @AppStorage("hasOpenedHelp") private var hasOpenedHelp: Bool = false

    var modelManager: ModelManager
    var autoScanRegistry: AutoScanRegistry

    enum SettingsTab: Hashable {
        case help, general, ai, autoscan, tags, wordBank, storage, about
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
            if !hasOpenedHelp {
                selection = .help
                hasOpenedHelp = true
            }
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
            sidebarRow(.help,     icon: "questionmark.circle", label: "Help & Tour")
            sidebarRow(.general,  icon: "gear",          label: "General")
            sidebarRow(.ai,       icon: "cpu",           label: "AI Models")
            sidebarRow(.autoscan, icon: "folder.badge.gearshape", label: "Auto-Scan")
            sidebarRow(.tags,     icon: "tag",           label: "Tag Library")
            sidebarRow(.wordBank, icon: "character.book.closed", label: "Word Bank")
            sidebarRow(.storage,  icon: "internaldrive", label: "Storage")
            sidebarRow(.about,    icon: "info.circle",   label: "About")
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
                case .help:     HelpView()
                case .general:  generalTab
                case .ai:       aiTab
                case .autoscan: AutoScanSettingsView(registry: autoScanRegistry)
                case .tags:     TagLibraryView()
                case .wordBank: WordBankView()
                case .storage:  storageTab
                case .about:    aboutTab
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
                Image(currentIconVariant.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ATHENS")
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

            AIDisclaimerView()

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

            Section("App Icon") {
                appIconPicker
            }

            Section("Tagging") {
                Toggle(isOn: $autoTagEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-tag new documents with AI")
                            .font(Japandi.Typography.body)
                            .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        Text("Uses the local tagger model to read each new document and assign tags + a 500-type document classification. Turn off to import without AI tagging — you can always run \u{201C}Auto Tag\u{201D} later.")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Japandi.Colors.accentFallback)

                Toggle(isOn: $lowPowerTagging) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Low power mode for tagging")
                            .font(Japandi.Typography.body)
                            .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        Text("Halves the CPU threads used during auto-tag so the fans stay quiet and the lid stays cool. Tagging takes ~2× longer per document. Good for laptop work; turn off for fastest tagging on a plugged-in machine.")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Japandi.Colors.accentFallback)
            }

            Section("Chat") {
                Toggle(isOn: $persistChatsAcrossSessions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Persist chat history across sessions")
                            .font(Japandi.Typography.body)
                            .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        Text("When on, leaving the chat surface and coming back picks up where you left off — and every chat is saved to history. Turn off if you'd rather treat each visit as a fresh in-memory session that vanishes when you navigate away.")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Japandi.Colors.accentFallback)
            }

            Section("Import") {
                Text("Imported files and documents added to the vault are processed automatically.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - App icon picker

    /// Persisted choice. Applied live via `NSApplication.shared
    /// .applicationIconImage` so the Dock + Cmd-Tab tile update without
    /// a relaunch, and re-applied on every launch from `AthenaeumApp`.
    @AppStorage("appIconVariant") private var appIconVariantRaw: String = AppIconVariant.ink.rawValue

    private var currentIconVariant: AppIconVariant {
        AppIconVariant(rawValue: appIconVariantRaw) ?? .ink
    }

    private var appIconPicker: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
            HStack(spacing: Japandi.Spacing.md) {
                ForEach(AppIconVariant.allCases) { variant in
                    appIconChoice(variant)
                }
                Spacer()
            }
            Text("Swaps the Dock icon and Cmd-Tab tile, and persists across relaunches. The Finder icon doesn't change — macOS reads that one from the app bundle.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appIconChoice(_ variant: AppIconVariant) -> some View {
        let isSelected = currentIconVariant == variant
        return Button {
            appIconVariantRaw = variant.rawValue
            AppIconApplier.apply(variant)
            NotificationCenter.default.post(name: .appIconVariantDidChange, object: nil)
        } label: {
            VStack(spacing: 6) {
                Image(variant.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? Japandi.Colors.accentFallback
                                    : Japandi.Colors.borderFallback,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Japandi.Colors.accentFallback)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 14, height: 14)
                                )
                                .offset(x: 6, y: -6)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: isSelected)

                HStack(spacing: 3) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Japandi.Colors.accentFallback)
                    }
                    Text(variant.displayName)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected
                                         ? Japandi.Colors.accentFallback
                                         : Japandi.Colors.textSecondaryFB)
                }
            }
            .frame(width: 80)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help(variant.helpText)
        .accessibilityLabel("\(variant.displayName) app icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.lg) {
            AIDisclaimerView()

            aiContextCard

            priorityTagsCard

            hardwareTierPickerCard

            inferenceEngineCard

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

    // MARK: - AI Context (about-you note)

    private var aiContextCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Context")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("A few lines about you that the local model reads on every chat turn and every auto-tag — domain, role, standing preferences. Empty is fine.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            TextEditor(text: $aiContextNote)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(8)
                .background(Japandi.Colors.surfaceRaisedFB)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if aiContextNote.isEmpty {
                Text("Example: \"I'm a security professional in LA studying cloud engineering at WGU. Files I care about most: medical (Kaiser), career planning, cloud certifications. I like concise technical answers — skip the marketing fluff.\"")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Spacer()
                    Text("\(aiContextNote.count) characters · injected into every chat + auto-tag prompt")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
            }
        }
        .padding(Japandi.Spacing.md)
        .background(Japandi.Colors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    // MARK: - Priority tags (retrieval re-ranker)

    private var priorityTagNames: [String] {
        priorityTagsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func togglePriorityTag(_ name: String) {
        let normalized = name.lowercased()
        var current = priorityTagNames
        if let idx = current.firstIndex(of: normalized) {
            current.remove(at: idx)
        } else {
            current.append(normalized)
        }
        priorityTagsRaw = current.joined(separator: ",")
    }

    private var priorityTagsCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Priority Tags")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("Tags you want surfaced first when chatting. Chunks from a priority-tagged document get a ×1.35 score boost during retrieval, so a borderline medical match floats above a stronger unrelated one.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !priorityTagNames.isEmpty {
                    Button {
                        priorityTagsRaw = ""
                    } label: {
                        Text("Clear")
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                    .buttonStyle(.plain)
                }
            }

            if allTags.isEmpty {
                Text("No tags yet. Import a document and let auto-tag populate your library, then come back to pick which tags you want prioritized.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Japandi.Spacing.xs)
            } else {
                let selected = Set(priorityTagNames)
                FlowLayout(spacing: 6) {
                    ForEach(allTags) { tag in
                        let isSelected = selected.contains(tag.name.lowercased())
                        Button {
                            togglePriorityTag(tag.name)
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(tag.name)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isSelected
                                    ? Japandi.Colors.accentFallback.opacity(0.85)
                                    : Japandi.Colors.surfaceRaisedFB
                            )
                            .foregroundStyle(
                                isSelected
                                    ? Color.white
                                    : Japandi.Colors.textSecondaryFB
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected
                                            ? Color.clear
                                            : Japandi.Colors.borderFallback,
                                        lineWidth: 0.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !priorityTagNames.isEmpty {
                HStack {
                    Spacer()
                    Text("\(priorityTagNames.count) prioritized · ×1.35 score boost during chat retrieval")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
            }
        }
        .padding(Japandi.Spacing.md)
        .background(Japandi.Colors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    // MARK: - Hardware tier picker

    private var hardwareTierPickerCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hardware Tier")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    Text("Auto: \(HardwareProfiler.detected.displayName) · \(String(format: "%.0f GB unified memory", HardwareProfiler.totalMemoryGB))")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
                Spacer()
            }

            Picker("Tier", selection: $hardwareTierOverride) {
                Text("Auto-detect").tag("auto")
                Divider()
                ForEach(HardwareTier.allCases, id: \.rawValue) { tier in
                    Text(tier.displayName).tag(tier.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: hardwareTierOverride) { _, _ in
                // Write the new tier's tunables into the shared keys so
                // LlamaInferenceConfig (n_ctx, GPU layers), RAGService
                // (chunk size, overlap, char budgets), and ChatView
                // (ragTopK) all pick them up on next read. Then notify
                // ModelManager + any tier observers.
                HardwareProfiler.applyTunablesForActiveTier()
                NotificationCenter.default.post(name: .hardwareTierDidChange, object: nil)
                NotificationCenter.default.post(name: .modelsDidChange, object: nil)
            }

            Text("Drives both the model lineup AND the runtime shape: chunk size, retrieval top-K, prompt budgets, and the inference context window all adapt to the chosen tier. Indexing and retrieval changes take effect immediately; loaded models reload on your next chat turn (expect a 5–15 s warmup once).")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Japandi.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumPane()
    }

    // MARK: - Inference engine

    private var inferenceEngine: InferenceEngine {
        InferenceEngine(rawValue: inferenceEngineRaw) ?? .llamaCpp
    }

    private var inferenceEngineCard: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inference Engine")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Spacer()
                if inferenceEngine == .mlx {
                    Text("EXPERIMENTAL")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Japandi.Colors.warmSoftFallback)
                        .foregroundStyle(Japandi.Colors.warmFallback)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: Japandi.Spacing.sm) {
                ForEach(InferenceEngine.allCases, id: \.rawValue) { engine in
                    engineOption(engine)
                }
            }

            if inferenceEngine == .mlx {
                HStack(spacing: Japandi.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Japandi.Colors.warmFallback)
                    Text("MLX runtime ships in a future build. You can download the recommended bundle below today, but tagging and chat run on llama.cpp until the runtime lands.")
                        .font(Japandi.Typography.caption)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Japandi.Spacing.xs)
                .background(Japandi.Colors.warmSoftFallback.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    private func engineOption(_ engine: InferenceEngine) -> some View {
        let isSelected = inferenceEngine == engine
        return Button {
            inferenceEngineRaw = engine.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: engine == .mlx ? "sparkles" : "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected
                                         ? Japandi.Colors.accentFallback
                                         : Japandi.Colors.textSecondaryFB)
                    Text(engine.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Japandi.Colors.accentFallback)
                    }
                }
                Text(engine.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Japandi.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(isSelected
                        ? Japandi.Colors.washFallback
                        : Japandi.Colors.bgFallback)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected
                                  ? Japandi.Colors.accentFallback
                                  : Japandi.Colors.borderFallback,
                                  lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
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

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .padding(.top, 2)
                Text("Presets change context window, GPU layers, chunk size, chunk overlap, and the RAG top-K (how many sources chat retrieves). New chats + new imports use the new values immediately. To re-chunk existing documents with the new settings, run Settings ▸ Storage ▸ Rebuild Vector Index.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .fixedSize(horizontal: false, vertical: true)
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

    @AppStorage("ragTopK") private var ragTopK: Int = 6

    private func apply(_ preset: SettingsPreset) {
        guard let values = preset.values else { return }
        contextSize  = values.contextSize
        maxGPULayers = values.gpuLayers
        chunkSize    = values.chunkSize
        chunkOverlap = values.chunkOverlap
        ragTopK      = values.ragTopK
    }

    private func matchesCurrentSettings(_ preset: SettingsPreset) -> Bool {
        guard let v = preset.values else { return false }
        return v.contextSize == contextSize
            && v.gpuLayers == maxGPULayers
            && v.chunkSize == chunkSize
            && v.chunkOverlap == chunkOverlap
            && v.ragTopK == ragTopK
    }

    // MARK: - Storage

    @State private var integrityReport: VaultIntegrityReport?
    @State private var integrityChecking = false
    @State private var backupProgress: BackupProgress?
    @State private var backupResult: BackupSummary?
    @State private var backupError: String?
    @State private var backupRunning = false

    private var storageTab: some View {
        Form {
            Section("Migration Backup") {
                VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encrypted one-click backup")
                                .font(Japandi.Typography.body)
                                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                            Text("Packages vault originals, a SwiftData JSON export, and local vector stores into one passphrase-protected .athensbackup archive for moving to a new Mac.")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if backupRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Create Backup...") {
                                createMigrationBackup()
                            }
                            .controlSize(.small)
                        }
                    }

                    if let backupProgress {
                        ProgressView(value: backupProgress.fraction)
                        Text(backupProgress.message)
                            .font(Japandi.Typography.caption)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let backupResult {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Japandi.Colors.accentFallback)
                            Text("Saved \(backupResult.documentCount) document records, \(backupResult.originalFileCount) originals, and \(backupResult.vectorStoreCount) vector stores to \(backupResult.destination.lastPathComponent).")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textSecondaryFB)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let backupError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Japandi.Colors.warmFallback)
                            Text(backupError)
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.warmFallback)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Section("Integrity") {
                VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vault integrity check")
                                .font(Japandi.Typography.body)
                                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                            Text("Walks every document and verifies its file still exists in the vault.")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                        Spacer()
                        if integrityChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Run check") {
                                runIntegrityCheck()
                            }
                            .controlSize(.small)
                        }
                    }
                    if let report = integrityReport {
                        integrityResultView(report)
                    } else if integrityChecking {
                        HStack(spacing: 6) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 10))
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            Text("Walking the vault…")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        }
                    } else {
                        // Helpful placeholder so the section doesn't render as
                        // an empty band sandwiched between the title and the
                        // next row. Disappears the first time a check is run.
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                            Text("No check has run yet. ATHENS will list any documents whose vault files have gone missing.")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rebuild vector index")
                                .font(Japandi.Typography.body)
                                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                            Text("Drops every embedding and re-embeds your live documents. Use this if chat returns sources you no longer have.")
                                .font(Japandi.Typography.caption)
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Rebuild now") {
                            NotificationCenter.default.post(name: .rebuildVectorIndex, object: nil)
                            dismiss()
                        }
                        .controlSize(.small)
                        .tint(Japandi.Colors.warmFallback)
                    }
                }
            }

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
                            Button("Reset to default") {
                                resetVaultToDefault()
                            }
                            .help("Recover from a stale bookmark (\u{201C}You don\u{2019}t have permission\u{2026}\u{201D})")
                            Button("Scan Now") {
                                NotificationCenter.default.post(name: .scanDocumentVault, object: nil)
                            }
                        }
                        .font(Japandi.Typography.caption)
                    }
                }

                Text("This is the local super folder. Files imported through ATHENS are copied here, and files you add in Finder are scanned and processed when the app opens.")
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

    // MARK: - Migration backup

    private func createMigrationBackup() {
        guard let destination = backupDestinationURL(),
              let passphrase = backupPassphrase() else {
            return
        }

        backupRunning = true
        backupResult = nil
        backupError = nil
        backupProgress = BackupProgress(message: "Starting backup...", completedBytes: 0, totalBytes: 0)

        Task { @MainActor in
            do {
                let summary = try await BackupService.shared.createBackup(
                    to: destination,
                    passphrase: passphrase,
                    context: integrityContext
                ) { progress in
                    backupProgress = progress
                }
                backupResult = summary
                backupProgress = nil
            } catch {
                backupError = error.localizedDescription
                NSSound.beep()
            }
            backupRunning = false
        }
    }

    private func backupDestinationURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create ATHENS Backup"
        panel.message = "Choose where to save the encrypted migration archive."
        panel.prompt = "Create Backup"
        panel.nameFieldStringValue = "ATHENS Backup \(Self.backupDateFormatter.string(from: Date())).athensbackup"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if url.pathExtension.lowercased() == "athensbackup" {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension("athensbackup")
    }

    private func backupPassphrase() -> String? {
        while true {
            let alert = NSAlert()
            alert.messageText = "Protect Backup"
            alert.informativeText = "Use this passphrase to unlock the archive on the new Mac. ATHENS does not store it."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")

            let passphraseField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            passphraseField.placeholderString = "Passphrase"
            let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            confirmField.placeholderString = "Confirm passphrase"

            let stack = NSStackView(views: [passphraseField, confirmField])
            stack.orientation = .vertical
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
            alert.accessoryView = stack

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            let passphrase = passphraseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let confirmation = confirmField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if passphrase.count >= 8, passphrase == confirmation {
                return passphrase
            }

            backupError = passphrase.count < 8
                ? "Backup passphrase must be at least 8 characters."
                : "Backup passphrases did not match."
            NSSound.beep()
        }
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

    // MARK: - Vault integrity

    /// Snapshot of a single vault check.
    struct VaultIntegrityReport {
        let totalDocuments: Int
        let missing: [(title: String, path: String)]
        let timestamp: Date

        var isClean: Bool { missing.isEmpty }
    }

    @Environment(\.modelContext) private var integrityContext

    /// The integrity check is a fast in-memory SwiftData fetch plus a few
    /// `FileManager.fileExists` syscalls. There's no reason to detach to a
    /// background actor — ModelContext isn't Sendable, and shoving it across
    /// the main-actor boundary is what Swift 6 strict concurrency flags.
    /// Run it inline on the main actor with a brief progress indicator.
    private func runIntegrityCheck() {
        integrityChecking = true
        Task { @MainActor in
            // Yield once so the spinner gets a chance to paint before we
            // start hammering the disk in the same run loop tick.
            await Task.yield()
            integrityReport = performIntegrityCheck(context: integrityContext)
            integrityChecking = false
        }
    }

    @MainActor
    private func performIntegrityCheck(context: ModelContext) -> VaultIntegrityReport {
        let fetch = FetchDescriptor<Document>()
        let docs = (try? context.fetch(fetch)) ?? []
        var missing: [(title: String, path: String)] = []
        for doc in docs {
            if let url = doc.storedFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                continue
            }
            // No vault file. If we still have the externally-stored backup
            // we don't treat it as missing — the reconciler can restore it.
            if doc.fileData != nil { continue }
            missing.append((title: doc.title, path: doc.storagePath ?? "—"))
        }
        return VaultIntegrityReport(
            totalDocuments: docs.count,
            missing: missing,
            timestamp: .now
        )
    }

    @ViewBuilder
    private func integrityResultView(_ report: VaultIntegrityReport) -> some View {
        HStack(spacing: 6) {
            Image(systemName: report.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(report.isClean ? Japandi.Colors.accentFallback : Japandi.Colors.warmFallback)
            if report.isClean {
                Text("\(report.totalDocuments) documents — every vault file is present.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            } else {
                Text("\(report.missing.count) of \(report.totalDocuments) document\(report.missing.count == 1 ? "" : "s") missing from vault.")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.warmFallback)
            }
        }
        if !report.isClean {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(report.missing.prefix(5), id: \.path) { entry in
                    HStack(spacing: 4) {
                        Text("·")
                        Text(entry.title)
                            .lineLimit(1)
                        Text(entry.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
                if report.missing.count > 5 {
                    Text("+\(report.missing.count - 5) more")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                }
            }
            .padding(.leading, Japandi.Spacing.sm)
        }
    }

    /// Drops the stored vault override and reverts to ~/Documents/Athenaeum
    /// Library. Use this when the prior vault URL is no longer accessible
    /// (e.g. the folder was deleted, or a UI-test bookmark went stale).
    private func resetVaultToDefault() {
        do {
            try DocumentVaultService.shared.resetToDefaultVault()
            vaultPath = DocumentVaultService.shared.vaultURL.path
            NotificationCenter.default.post(name: .scanDocumentVault, object: nil)
        } catch {
            NSSound.beep()
        }
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose ATHENS Document Vault"
        panel.message = "Choose the local folder where ATHENS stores and watches your documents."
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
        /// RAG top-K — how many retrieved chunks the chat surfaces per turn.
        /// More chunks = more context fed to the LLM, at the cost of tokens.
        let ragTopK: Int
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
            return Values(contextSize: 4096, gpuLayers: -1, chunkSize: 512, chunkOverlap: 64, ragTopK: 6)
        case .powerUser:
            return Values(contextSize: 8192, gpuLayers: -1, chunkSize: 768, chunkOverlap: 128, ragTopK: 10)
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
