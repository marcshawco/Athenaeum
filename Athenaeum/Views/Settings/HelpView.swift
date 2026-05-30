import SwiftUI

// MARK: - Help & Tour
//
// Settings panel that gives new users a guided tour and answers the questions
// every adult-with-a-Mac asks ("where do my files go?", "is this private?",
// "why is it slow?"). Designed to scan well at a glance for casual users
// while embedding enough specifics — shortcuts, file paths, internals —
// that power users don't feel babied.

struct HelpView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case quickStart = "Quick Start"
        case faq = "FAQ"
        case power = "Power Tips"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .quickStart

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            header
            modePicker

            ScrollView {
                VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
                    switch mode {
                    case .quickStart: quickStartContent
                    case .faq:        faqContent
                    case .power:      powerContent
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, Japandi.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Help & Tour")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
            Text("A short tour, plain-English answers, and the keyboard shortcuts that make ATHENS sing.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Quick Start

    private var quickStartContent: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            tourCard(
                step: "01",
                title: "Get your first document in",
                blurb: "Hit ⌘I (or File ▸ Import Documents), pick a PDF, image, receipt, lease — anything in your Documents folder. ATHENS copies it into a private vault, reads the text, summarizes it, and assigns tags. No internet involved.",
                power: "Drag and drop also works anywhere on the grid. Settings ▸ Storage ▸ Reveal Vault opens the exact folder in Finder — by default it's in ATHENS's sandboxed container, or anywhere you picked via Choose Folder."
            )

            tourCard(
                step: "02",
                title: "Watch a whole folder",
                blurb: "Got a Downloads folder full of receipts? Settings ▸ Auto-Scan ▸ Add folder, point at it, and ATHENS will quietly import anything new the moment Finder finishes writing. Drop receipts in, walk away, come back to a tagged archive.",
                power: "Backed by FSEventStream with a 2.5 s debounce and a path+mtime fingerprint so the same file isn't reimported on every save."
            )

            tourCard(
                step: "03",
                title: "Ask your library a question",
                blurb: "Click Document Chat in the sidebar and try \u{201C}how much did I spend on the Tokyo trip?\u{201D} or \u{201C}what's the renewal date on my lease?\u{201D}. ATHENS finds the relevant passages from your documents and writes an answer with citations.",
                power: "Vector embeddings + cosine similarity. The Sources panel and each assistant turn's \u{201C}N sources used\u{201D} disclosure shows exactly which chunks the model saw."
            )

            tourCard(
                step: "04",
                title: "Pick the right models",
                blurb: "On first launch, head to Model Status (sidebar bottom) and click Download on each tile. Qwen 2.5 14B handles both tagging and chat (one file, two jobs), Nomic Embed v1.5 produces retrieval vectors, MiniCPM-V does smart OCR on scanned pages. About 14 GB total. Everything runs on your Mac — Settings ▸ AI Models ▸ Analyze My Mac picks the right defaults for your hardware.",
                power: "GGUF Q4_K_M quants via llama.cpp + Metal. The Inference Engine setting lets you also stage an MLX bundle for Apple silicon."
            )

            tourCard(
                step: "05",
                title: "Tidy your tags",
                blurb: "Tags are auto-generated, but you're in charge. Settings ▸ Tag Library lets you rename, hide, or delete tags. Renaming into an existing tag merges them. Anything you hide disappears from the sidebar without touching the documents themselves.",
                power: "Hidden tag names live in @AppStorage(\"hiddenTags\") as a comma-joined list. The sidebar reads it on every render."
            )

            calloutCard(
                icon: "lock.shield",
                title: "Everything stays local",
                body: "Nothing leaves your Mac. The models run on-device, files live in a Finder folder you control, and the only network calls ATHENS makes are when you click Download in Model Status. The status bar at the bottom says \u{201C}local · private\u{201D} for a reason."
            )
        }
    }

    // MARK: - FAQ

    private var faqContent: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.xs) {
            ForEach(faqEntries, id: \.q) { entry in
                FAQRow(question: entry.q, answer: entry.a, detail: entry.d)
            }
        }
    }

    private struct FAQEntry {
        let q: String
        let a: String
        let d: String?
    }

    private var faqEntries: [FAQEntry] {
        [
            FAQEntry(
                q: "Is any of my data sent to a server?",
                a: "No. Every model runs on your Mac. Documents, chats, tags, embeddings — all of it sits inside your sandboxed Application Support folder and your chosen vault. The only network requests ATHENS makes are when you press Download in Model Status to fetch the open-source models from Hugging Face.",
                d: "Sandbox entitlements limit access to user-selected folders. App Transport Security is on. Outbound calls hit huggingface.co only during a download."
            ),
            FAQEntry(
                q: "Where do my files actually live?",
                a: "Originals live in your ATHENS vault folder — by default the app's sandboxed container, or anywhere you picked via Settings ▸ Storage ▸ Choose Folder. Reveal Vault opens it in Finder. Derived data — text extracted from PDFs, the search index, AI summaries — lives in the app's Application Support folder (Settings ▸ Storage shows the exact path).",
                d: "Default vault: ~/Library/Containers/com.shawhause.athens/Data/Documents/Athenaeum Library. Vault path is persisted as a security-scoped bookmark. Reset to default clears stale ones. Vector store: ~/Library/Containers/com.shawhause.athens/Data/Library/Application Support/Athenaeum/vector_store.json."
            ),
            FAQEntry(
                q: "Why did ATHENS tag my document wrong?",
                a: "Local AI is good but not perfect. Click the document, hit the chevron next to the type pill, and pick the right type from the 500-type list. The next time you reprocess, the model learns from the broader set of corrected examples — but more practically, your override sticks immediately.",
                d: "Override stored as Document.documentTypeSlug + categorySlug. Searchable text is rebuilt so search and \u{201C}By Category\u{201D} reflect it instantly."
            ),
            FAQEntry(
                q: "Why is chat slow or saying \u{201C}Token decode failed\u{201D}?",
                a: "Long histories + lots of retrieved chunks can overflow the model's context. Either ask a shorter question, start a fresh chat, or open Settings ▸ Storage and tap Rebuild Vector Index. If old documents you've deleted are still showing up as sources, that's exactly what the rebuild fixes.",
                d: "Context cap is 4K tokens. RAG over-fetches 4× and filters to live SwiftData IDs, then trims to 8K chars / 1200 chars per chunk."
            ),
            FAQEntry(
                q: "Can I import a whole folder at once?",
                a: "Yes — two ways. File ▸ Scan Folder for Import (⇧⌘I) walks a folder once and imports everything that matches. Settings ▸ Auto-Scan adds a folder that gets watched forever, so new files appear in ATHENS without you doing anything.",
                d: "Recursive enumerator with .skipsHiddenFiles + .skipsPackageDescendants. Allow-list defined in AutoScanCoordinator.supportedExtensions."
            ),
            FAQEntry(
                q: "What if I delete a document by accident?",
                a: "The vault file is moved to Trash, so you can drag it back. The ATHENS record (tags, summary, embeddings) is gone unless you reimport — at which point a fresh pipeline runs.",
                d: "Delete path: FileManager.trashItem + modelContext.delete + ragService.removeDocument(id:). Embeddings are dropped from the vector store on delete."
            ),
            FAQEntry(
                q: "Can I back this up?",
                a: "Yes. Time Machine works because everything lives in your home folder. For a portable copy, open Settings ▸ Storage and use Create Backup. ATHENS makes one encrypted .athensbackup file with originals, SwiftData JSON, and vector stores for moving to a new Mac.",
                d: "Backup includes manifest.json, SwiftData/swiftdata-export.json, Originals/Vault, Originals/Recovered when needed, and VectorStores/vector_store*.json. The passphrase is required to unlock it."
            ),
            FAQEntry(
                q: "Which models do I actually need?",
                a: "Qwen 2.5 14B is the generalist — it handles both tagging AND chat from a single file. Nomic Embed v1.5 generates the retrieval vectors that power RAG search and chat citations. MiniCPM-V is only needed for scanned PDFs or photographed receipts where the text isn't selectable. All three are required for the full experience; without them you fall back to offline rules + Apple Vision OCR.",
                d: "Roles: .tagger / .chat (share Qwen 14B), .embedding (Nomic), .vision (MiniCPM-V). Offline fallback uses OfflineDocumentClassifier + Apple Vision OCR."
            ),
            FAQEntry(
                q: "What's that green pill under each document title?",
                a: "That's ATHENS's best guess at what kind of document it is, based on the 500-type reference taxonomy (Lease Agreement, Marriage Certificate, IRS Form 1040, etc.). Click it to confirm or change.",
                d: "DocumentTaxonomy.allTypes — 500 entries × 20 categories, anchored to a markdown reference guide."
            ),
            FAQEntry(
                q: "How accurate is the OCR on scanned receipts?",
                a: "Apple's Vision framework is excellent for printed text on flat backgrounds. Add the MiniCPM-V vision model and you also get an LLM cleanup pass that handles tilted scans, handwriting, and weird fonts.",
                d: "Default path: Vision OCR. With MiniCPM-V loaded: vision model post-edits Vision OCR output."
            ),
            FAQEntry(
                q: "Why is the right inspector dark when the rest of the app is cream?",
                a: "It's intentional — the dark moss panel keeps the document details feeling like a stage-lit reading room next to the bright paper library. You'll find your documents read well against it.",
                d: "Hardcoded Japandi.Colors.inspectorBg (#243A2D). The rest of the palette respects light/dark mode."
            ),
            FAQEntry(
                q: "Can I use my own models?",
                a: "Yes. Drop any GGUF file into the app's Models folder (Model Status → Reveal in Finder opens it directly) with the expected filename and ATHENS will pick it up on next launch.",
                d: "Filenames: Qwen2.5-14B-Instruct-Q4_K_M.gguf (tagger + chat) · nomic-embed-text-v1.5.Q4_K_M.gguf (embeddings) · ggml-model-Q4_K_M.gguf (MiniCPM-V)."
            ),
        ]
    }

    // MARK: - Power Tips

    private var powerContent: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            shortcutsCard
            advancedCard
            internalsCard
        }
    }

    private var shortcutsCard: some View {
        sectionCard(title: "Keyboard Shortcuts", icon: "command") {
            VStack(alignment: .leading, spacing: Japandi.Spacing.xxs) {
                ShortcutRow(combo: "⌘ I",     desc: "Import documents (file picker)")
                ShortcutRow(combo: "⇧⌘ I",   desc: "Scan a folder for import (one-shot)")
                ShortcutRow(combo: "⌘ ,",     desc: "Open Settings")
                ShortcutRow(combo: "⇧⌘ O",   desc: "Reveal the document vault in Finder")
                ShortcutRow(combo: "⇧⌘ R",   desc: "Re-scan the document vault now")
                ShortcutRow(combo: "Space",    desc: "Quick Look the selected document (Finder-style)")
                ShortcutRow(combo: "↩",       desc: "Open in the document chat (when selected)")
                ShortcutRow(combo: "⌘ K",     desc: "Focus the search bar")
                ShortcutRow(combo: "Esc",      desc: "Dismiss any sheet (Settings, picker, dialog)")
            }
        }
    }

    private var advancedCard: some View {
        sectionCard(title: "Hidden gems", icon: "sparkles") {
            VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
                bulletRow(
                    title: "Smart Collections in the sidebar",
                    body: "By Category appears automatically once you have documents — every taxonomy category with at least one doc gets a row, sorted by how busy it is."
                )
                bulletRow(
                    title: "Hardware-aware presets",
                    body: "Settings ▸ AI Models ▸ Analyze My Mac reads your core count + RAM, picks the right context window and chunk size, and one-click applies it. Pro tier on >16 GB Macs."
                )
                bulletRow(
                    title: "Re-index banner",
                    body: "When the vector index drifts behind your library (e.g. after pulling models down for the first time), a top banner appears with a one-click \u{201C}Re-index now\u{201D}."
                )
                bulletRow(
                    title: "Citations per assistant turn",
                    body: "Every answer in Document Chat has its own \u{201C}N sources used\u{201D} chevron beneath it. Expand to see which chunks the model actually read."
                )
                bulletRow(
                    title: "MLX dual-engine",
                    body: "Settings ▸ AI Models ▸ Inference Engine lets you pre-download the Apple silicon-optimized Qwen 2.5 7B 4-bit MLX bundle. The runtime is staged for a future build."
                )
                bulletRow(
                    title: "Vault integrity check",
                    body: "Settings ▸ Storage ▸ Integrity verifies every document's file is where ATHENS thinks it is, and lists any orphans."
                )
                bulletRow(
                    title: "Hide ugly tags",
                    body: "Tag Library has an eye toggle per tag. Hidden tags vanish from the sidebar without losing the data behind them."
                )
            }
        }
    }

    private var internalsCard: some View {
        sectionCard(title: "Under the hood", icon: "gearshape.2") {
            VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
                bulletRow(
                    title: "Models",
                    body: "llama.cpp via the prebuilt llama.xcframework. Four roles: tagger + chat both ride Qwen 2.5 14B Q4_K_M (one file, shared in-RAM context), embedding uses Nomic Embed Text v1.5 Q4_K_M, vision uses MiniCPM-V 2.6 Q4_K_M. GPU layers default to All on Apple silicon."
                )
                bulletRow(
                    title: "Retrieval",
                    body: "VectorStore is a simple actor-isolated JSON file of EmbeddingEntry rows; cosine similarity via Accelerate's vDSP. RAG over-fetches 4×, filters to live document IDs, returns the top K (default 5)."
                )
                bulletRow(
                    title: "Taxonomy",
                    body: "500 document types × 20 categories generated from the markdown reference guide. Drives the document_type / category fields and the By-Category sidebar."
                )
                bulletRow(
                    title: "Persistence",
                    body: "SwiftData for Document + Tag (~/Library/Application Support/Athenaeum/default.store). Settings via @AppStorage. Auto-scan folders are JSON-encoded in UserDefaults with security-scoped bookmarks."
                )
                bulletRow(
                    title: "Privacy",
                    body: "App is sandboxed. Outbound network is gated on you pressing Download. Vault access uses NSOpenPanel + security-scoped bookmarks; the app never browses your filesystem on its own."
                )
            }
        }
    }

    // MARK: - Reusable bits

    private func tourCard(step: String, title: String, blurb: String, power: String) -> some View {
        HStack(alignment: .top, spacing: Japandi.Spacing.md) {
            Text(step)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Japandi.Colors.accentFallback)
                .frame(width: 30, height: 30)
                .background(Japandi.Colors.washFallback)
                .overlay(
                    Circle().strokeBorder(Japandi.Colors.accentFallback.opacity(0.25), lineWidth: 0.5)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text(blurb)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                        .foregroundStyle(Japandi.Colors.accentMutedFallback)
                    Text(power)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Japandi.Colors.textTertiaryFB)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
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

    private func calloutCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Japandi.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.accentFallback)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text(body)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Japandi.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Japandi.Colors.washFallback)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.accentFallback.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.accentFallback)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
            }
            content()
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

    private func bulletRow(title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Japandi.Spacing.xs) {
            Circle()
                .fill(Japandi.Colors.accentMutedFallback)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text(body)
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Sub-components

private struct FAQRow: View {
    let question: String
    let answer: String
    let detail: String?

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isOpen.toggle() }
            } label: {
                HStack(alignment: .center, spacing: Japandi.Spacing.xs) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Japandi.Colors.accentFallback)
                        .frame(width: 10)
                    Text(question)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Japandi.Colors.textPrimaryFB)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, Japandi.Spacing.sm)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text(answer)
                        .font(Japandi.Typography.body)
                        .foregroundStyle(Japandi.Colors.textSecondaryFB)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 9))
                                .foregroundStyle(Japandi.Colors.accentMutedFallback)
                                .padding(.top, 2)
                            Text(detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                                .lineSpacing(1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Japandi.Spacing.sm)
                .padding(.leading, 16)
                .padding(.bottom, Japandi.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }
}

private struct ShortcutRow: View {
    let combo: String
    let desc: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Japandi.Spacing.sm) {
            Text(combo)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Japandi.Colors.washFallback)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Japandi.Colors.accentFallback.opacity(0.20), lineWidth: 0.5)
                )
                .frame(width: 76, alignment: .leading)
            Text(desc)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
            Spacer(minLength: 0)
        }
    }
}
