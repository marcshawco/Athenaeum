# Athenaeum

Athenaeum is a private, local-first macOS document library. It imports personal and business documents into a Finder-visible vault, extracts searchable text, applies local AI-assisted metadata, and lets you ask questions across the archive with on-device retrieval-augmented generation.

The app is built with SwiftUI, SwiftData, Vision, PDFKit, and a bundled llama.cpp framework for GGUF model inference. It is designed around the idea that sensitive documents should stay on the Mac.

## What It Does

- Imports PDFs, images, text files, Word documents, spreadsheets, presentations, emails, calendar files, and other common document formats.
- Stores originals in a local document vault, defaulting to `~/Documents/Athenaeum Library`.
- Extracts text from PDFs and common text formats, with Apple Vision OCR for images and scanned documents.
- Classifies documents with a 1,100+-term controlled tag vocabulary and local LLM tagging.
- Tracks titles, filenames, file types, sizes, correspondents, dates, summaries, tags, processing state, and searchable text in SwiftData.
- Builds a local vector index for document chunks and supports document chat through RAG.
- **Auto-tiers the model lineup to the host Mac** — 8 GB MacBook Airs run a Compact set (Qwen 3B); 16 GB Macs get Standard (Qwen 7B + MiniCPM-V); 24+ GB machines unlock Performance (Qwen 14B + MiniCPM-V). User-overridable in Settings.
- Sidebar tags are user-pinned (cap 10); a dedicated **All Tags** screen browses the full vocabulary with A–Z grouping, search, and right-click pin/unpin.
- Bulk batch actions for selected documents: tag, auto-tag, clear tags, auto-name, export, delete.
- Exports originals, extracted text, JSON metadata, or CSV catalog rows.

## Project Structure

```text
Athenaeum/
  AthenaeumApp.swift          App entry point, commands, SwiftData container
  ContentView.swift           Main navigation, service setup, vault scanning
  Models/                     SwiftData document and tag models
  Services/                   Import, OCR, metadata, search, RAG, LLM, vault, export
  Theme/                      Japandi visual system and view modifiers
  Views/                      Sidebar, library, detail, chat, settings, onboarding
  Assets.xcassets/            App icon, brand marks, color assets

Tools/                        Standalone smoke tests for vault/import/RAG behavior
brand/                        Source brand assets and exported icons
llama.xcframework/            Bundled llama.cpp framework used by the app target
Athenaeum.xcodeproj/          Xcode project
```

## Architecture

Athenaeum starts in `AthenaeumApp`, which creates the SwiftData model container for `Document` and `Tag`, registers app commands, and opens `ContentView`.

`ContentView` wires the core services together:

- `DocumentVaultService` owns the user-visible vault and security-scoped folder access.
- `DocumentVaultMonitor` watches the vault for Finder-added documents.
- `DocumentProcessor` orchestrates import, text extraction, metadata refinement, classification, persistence, and RAG indexing.
- `VisionOCRService` handles native OCR for images and scanned documents.
- `LocalLLMService` uses `LlamaContext` actors to load and run local models. Two roles that point at the same file share a single in-RAM context.
- `VectorStore` persists embeddings for local semantic search. It detects embedding-dimension mismatches on load so the library can be re-embedded when the embedder changes.
- `RAGService` chunks documents, generates retrieval-tuned embeddings with the dedicated embedding model, retrieves relevant context, and streams chat answers with citations.
- `ModelDownloader` downloads the configured GGUF models into Application Support. Both this and `LLMModelDescriptor.defaults` are tier-aware — see *Local Models → Hardware tiers* below.
- `HardwareProfiler` reads available unified memory and resolves a `HardwareTier` (Compact / Standard / Performance / Workstation). The user can override the auto-detected tier from Settings; everything downstream picks up the change via `NotificationCenter.modelsDidChange`.

The UI is organized around a three-pane macOS layout: sidebar navigation, a library or chat content area, and an inspector-style detail/preview pane.

## Local Models

Athenaeum looks for GGUF models in:

```text
~/Library/Application Support/Athenaeum/Models
```

### Hardware tiers

This is a documentation app, not a benchmark — Athenaeum picks the lightest lineup that does the job well on the host Mac. `HardwareProfiler` reads `ProcessInfo.processInfo.physicalMemory` at launch and chooses a tier:

| Tier | RAM | Tagger + Chat | Embedding | Vision | On-disk |
| --- | --- | --- | --- | --- | --- |
| **Compact** | < 12 GB | Qwen 2.5 3B Instruct Q4_K_M | Nomic Embed v1.5 | — (Apple Vision OCR) | ~2 GB |
| **Standard** | 12–20 GB | Qwen 2.5 7B Instruct Q4_K_M | Nomic Embed v1.5 | MiniCPM-V 2.6 Q4_K_M | ~10 GB |
| **Performance** | 20–40 GB | Qwen 2.5 14B Instruct Q4_K_M | Nomic Embed v1.5 | MiniCPM-V 2.6 Q4_K_M | ~14 GB |
| **Workstation** | ≥ 40 GB | Qwen 2.5 14B Instruct Q4_K_M | Nomic Embed v1.5 | MiniCPM-V 2.6 Q4_K_M | ~14 GB |

The user can override the auto-detected tier in **Settings → AI Models** (Auto-detect / Compact / Standard / Performance / Workstation). Model Status surfaces the active tier with a rationale, the detected RAM, and the model tiles for the chosen lineup.

### Per-role model duties

- **Tagger + Chat** share a single GGUF file. `LocalLLMService.contextForRole` notices the shared filename and reuses one in-RAM `LlamaContext` instead of loading the weights twice.
- **Embedding** uses Nomic Embed Text v1.5 (768-dim, contrastively trained). `RAGService` prepends the model's required `search_document:` / `search_query:` task prefixes.
- **Vision** uses MiniCPM-V 2.6 for enhanced OCR on scanned PDFs and photographed receipts when Apple's native Vision framework alone isn't enough. Skipped entirely on Compact tier.

### Fallbacks and migrations

Document import still works without models installed; Athenaeum falls back to native text extraction, Apple Vision OCR, and a rule-based offline classifier where possible.

When the active embedder's output dimension stops matching what's persisted in the vector store, the store wipes itself on next launch and `indexExistingDocumentsIfNeeded` re-embeds the library in the background. The same flow handles tier changes that swap the embedder.

### Diagnostics

Every tagging attempt is mirrored to a permanent log at:

```text
~/Library/Containers/<bundle-id>/Data/Library/Application Support/Athenaeum/tagger.log
```

(or the equivalent unsandboxed path if you're running outside the sandbox). Lines include the prompt length, the raw model response, the parsed tags, the post-validation tags, and explicit `UNPARSEABLE JSON` / `THREW` markers when the LLM stumbles.

## Requirements

- macOS 15.7 or newer, based on the current Xcode deployment target.
- Xcode with the macOS SDK.
- Apple Silicon or Intel Mac supported by the bundled `llama.xcframework`.
- Several GB of free disk space if downloading the default local models.

## Build

Open `Athenaeum.xcodeproj` in Xcode and run the `Athenaeum` scheme.

From the command line:

```sh
xcodebuild -project Athenaeum.xcodeproj -scheme Athenaeum -configuration Debug build
```

## Smoke Tests

The `Tools/` directory contains standalone Swift smoke tests for core flows. They are not currently wired into an Xcode test target, but they document and exercise the expected behavior for vault storage, import processing, fallback tagging, OCR, RAG, and export paths.

## Privacy

Athenaeum is intentionally local-first:

- Original files live in the local document vault.
- Metadata is stored locally with SwiftData.
- Vector indexes are stored locally.
- AI inference is designed to run through local GGUF models.

The app includes network client entitlement so it can download models from Hugging Face when requested.
