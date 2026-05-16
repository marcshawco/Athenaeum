# Athenaeum

Athenaeum is a private, local-first macOS document library. It imports personal and business documents into a Finder-visible vault, extracts searchable text, applies local AI-assisted metadata, and lets you ask questions across the archive with on-device retrieval-augmented generation.

The app is built with SwiftUI, SwiftData, Vision, PDFKit, and a bundled llama.cpp framework for GGUF model inference. It is designed around the idea that sensitive documents should stay on the Mac.

## What It Does

- Imports PDFs, images, text files, Word documents, spreadsheets, presentations, emails, calendar files, and other common document formats.
- Stores originals in a local document vault, defaulting to `~/Documents/Athenaeum Library`.
- Extracts text from PDFs and common text formats, with Apple Vision OCR for images and scanned documents.
- Classifies documents with a built-in controlled tag vocabulary and optional local LLM tagging.
- Tracks titles, filenames, file types, sizes, correspondents, dates, summaries, tags, processing state, and searchable text in SwiftData.
- Builds a local vector index for document chunks and supports document chat through RAG.
- Downloads and manages local GGUF models from Hugging Face.
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
- `LocalLLMService` uses `LlamaContext` actors to load and run local models.
- `VectorStore` persists embeddings for local semantic search.
- `RAGService` chunks documents, retrieves relevant context, and streams chat answers with citations.
- `ModelDownloader` downloads the configured GGUF models into Application Support.

The UI is organized around a three-pane macOS layout: sidebar navigation, a library or chat content area, and an inspector-style detail/preview pane.

## Local Models

Athenaeum looks for GGUF models in:

```text
~/Library/Application Support/Athenaeum/Models
```

The current model roles are:

| Role | Default model | Purpose |
| --- | --- | --- |
| Tagger | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | Metadata and tag classification |
| Chat | `Mistral-7B-Instruct-v0.3-Q4_K_M.gguf` | Document chat and embeddings |
| Vision | `ggml-model-Q4_K_M.gguf` | Enhanced OCR path when available |

Models can be downloaded from the app's Model Status screen. Document import still works without models installed; Athenaeum falls back to local extraction and rule-based classification where possible.

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
