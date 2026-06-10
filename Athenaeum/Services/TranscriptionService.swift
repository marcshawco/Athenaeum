@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

// MARK: - Local Whisper transcription

/// MVP speech-to-text bridge for local audio/video imports.
///
/// The app owns the document pipeline; Whisper owns speech recognition. This
/// service looks for a local `whisper-cli` plus a GGML Whisper model, extracts
/// media to a temporary 16 kHz mono WAV, then returns the transcript text.
actor TranscriptionService {
    enum TranscriptionError: LocalizedError {
        case missingWhisperCLI([String])
        case missingWhisperModel([String])
        case noAudioTrack
        case audioExtractionFailed(String)
        case whisperFailed(String)
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .missingWhisperCLI(let paths):
                return """
                Local transcription needs whisper-cli. Install whisper.cpp and place whisper-cli at one of: \(paths.joined(separator: ", ")).
                """
            case .missingWhisperModel(let paths):
                return """
                Local transcription needs a Whisper GGML model. Place one at one of: \(paths.joined(separator: ", ")).
                """
            case .noAudioTrack:
                return "No audio track was found to transcribe."
            case .audioExtractionFailed(let detail):
                return "Could not prepare audio for transcription: \(detail)"
            case .whisperFailed(let detail):
                return "Whisper transcription failed: \(detail)"
            case .emptyTranscript:
                return "Whisper finished, but did not produce transcript text."
            }
        }
    }

    nonisolated func canHandle(url: URL, uti: String) -> Bool {
        if let type = UTType(uti),
           type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return true
        }

        return Self.mediaExtensions.contains(url.pathExtension.lowercased())
    }

    func transcribe(url: URL, uti: String) async throws -> String {
        guard let whisperCLI = Self.firstExistingURL(in: Self.whisperCLICandidates) else {
            throw TranscriptionError.missingWhisperCLI(Self.whisperCLICandidates.map(\.path))
        }
        guard let modelURL = Self.firstExistingURL(in: Self.modelCandidates) else {
            throw TranscriptionError.missingWhisperModel(Self.modelCandidates.map(\.path))
        }

        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("athens-transcribe-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let outputBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("athens-transcript-\(UUID().uuidString)")
        let outputTextURL = outputBaseURL.appendingPathExtension("txt")

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: outputTextURL)
        }

        try await exportMonoWAV(from: url, to: wavURL)
        try await runWhisper(cli: whisperCLI, model: modelURL, audio: wavURL, outputBase: outputBaseURL)

        let transcript = (try? String(contentsOf: outputTextURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !transcript.isEmpty else { throw TranscriptionError.emptyTranscript }
        return transcript
    }

    // MARK: - Paths

    private static let mediaExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac",
        "mp4", "m4v", "mov", "avi", "mkv", "webm",
    ]

    private static var appSupportRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Athenaeum", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var whisperCLICandidates: [URL] {
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["ATHENS_WHISPER_CLI"], !env.isEmpty {
            urls.append(URL(fileURLWithPath: env))
        }
        urls.append(contentsOf: [
            appSupportRoot.appendingPathComponent("Whisper/whisper-cli"),
            appSupportRoot.appendingPathComponent("Whisper/main"),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
            URL(fileURLWithPath: "/opt/homebrew/bin/main"),
            URL(fileURLWithPath: "/usr/local/bin/main"),
        ])
        return urls
    }

    private static var modelCandidates: [URL] {
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["ATHENS_WHISPER_MODEL"], !env.isEmpty {
            urls.append(URL(fileURLWithPath: env))
        }
        let names = [
            "ggml-small.en.bin",
            "ggml-small.bin",
            "ggml-base.en.bin",
            "ggml-base.bin",
            "ggml-tiny.en.bin",
            "ggml-tiny.bin",
        ]
        for base in [
            appSupportRoot.appendingPathComponent("Whisper/Models", isDirectory: true),
            appSupportRoot.appendingPathComponent("Models", isDirectory: true),
        ] {
            urls.append(contentsOf: names.map { base.appendingPathComponent($0) })
        }
        return urls
    }

    private static func firstExistingURL(in urls: [URL]) -> URL? {
        urls.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    // MARK: - Audio extraction

    private func exportMonoWAV(from sourceURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else { throw TranscriptionError.noAudioTrack }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: settings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw TranscriptionError.audioExtractionFailed("The audio track could not be read.")
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw TranscriptionError.audioExtractionFailed("The WAV writer could not be configured.")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw TranscriptionError.audioExtractionFailed(reader.error?.localizedDescription ?? "Reader did not start.")
        }
        guard writer.startWriting() else {
            throw TranscriptionError.audioExtractionFailed(writer.error?.localizedDescription ?? "Writer did not start.")
        }
        writer.startSession(atSourceTime: .zero)

        let exporter = AudioExportSession(
            reader: reader,
            readerOutput: readerOutput,
            writer: writer,
            writerInput: writerInput
        )
        try await exporter.export()
    }

    // MARK: - Whisper

    private func runWhisper(cli: URL, model: URL, audio: URL, outputBase: URL) async throws {
        let process = Process()
        process.executableURL = cli
        process.arguments = [
            "-m", model.path,
            "-f", audio.path,
            "-otxt",
            "-of", outputBase.path,
            "-nt",
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8).flatMap(Self.nilIfBlank) ?? "Exit code \(process.terminationStatus)"
            throw TranscriptionError.whisperFailed(message)
        }
    }

    private static func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class AudioExportSession: @unchecked Sendable {
    nonisolated(unsafe) private let reader: AVAssetReader
    nonisolated(unsafe) private let readerOutput: AVAssetReaderTrackOutput
    nonisolated(unsafe) private let writer: AVAssetWriter
    nonisolated(unsafe) private let writerInput: AVAssetWriterInput

    nonisolated init(
        reader: AVAssetReader,
        readerOutput: AVAssetReaderTrackOutput,
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput
    ) {
        self.reader = reader
        self.readerOutput = readerOutput
        self.writer = writer
        self.writerInput = writerInput
    }

    nonisolated func export() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "athens.transcription.audio-export")
            writerInput.requestMediaDataWhenReady(on: queue) { [self] in
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        if reader.status == .failed || reader.status == .cancelled {
                            writer.cancelWriting()
                            continuation.resume(throwing: TranscriptionService.TranscriptionError.audioExtractionFailed(reader.error?.localizedDescription ?? reader.status.rawValue.description))
                            return
                        }
                        writer.finishWriting { [self] in
                            if writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: TranscriptionService.TranscriptionError.audioExtractionFailed(writer.error?.localizedDescription ?? writer.status.rawValue.description))
                            }
                        }
                        return
                    }
                }
            }
        }
    }
}
