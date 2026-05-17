import SwiftUI
import AppKit

// MARK: - Auto-Scan Folders Settings
//
// Settings panel for managing folders that Athenaeum continuously watches.
// New files dropped into any enabled folder are auto-imported + auto-tagged
// through the same pipeline as manual import.

struct AutoScanSettingsView: View {
    let registry: AutoScanRegistry

    @State private var removeTarget: AutoScanFolder?

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            header
            folderList
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .confirmationDialog(
            removeTarget.map { "Stop watching \u{201C}\($0.displayName)\u{201D}?" } ?? "Stop watching folder?",
            isPresented: Binding(
                get: { removeTarget != nil },
                set: { if !$0 { removeTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: removeTarget
        ) { folder in
            Button("Remove", role: .destructive) {
                registry.removeFolder(folder.id)
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: { folder in
            Text("Documents already imported from \(folder.path) stay in ATHENS. The folder itself is left untouched.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Auto-Scan Folders")
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
            Text("ATHENS continuously watches these folders. Anything dropped in is imported, tagged, and indexed automatically.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Folder list

    @ViewBuilder
    private var folderList: some View {
        if registry.folders.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(registry.folders) { folder in
                    folderRow(folder)
                    Divider().foregroundStyle(Japandi.Colors.borderFallback)
                }
            }
            .background(Japandi.Colors.surfaceRaisedFB)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.borderFallback)
            Text("No folders being watched")
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
            Text("Click \u{201C}Add folder\u{2026}\u{201D} to start a watcher. ATHENS will scan the folder once on launch, then again whenever Finder writes to it.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Japandi.Spacing.lg)
        .background(Japandi.Colors.surfaceRaisedFB)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Japandi.Colors.borderFallback, lineWidth: 0.5)
        )
    }

    private func folderRow(_ folder: AutoScanFolder) -> some View {
        HStack(spacing: Japandi.Spacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(folder.isEnabled
                                 ? Japandi.Colors.accentFallback
                                 : Japandi.Colors.textTertiaryFB)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.displayName)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(folder.isEnabled
                                     ? Japandi.Colors.textPrimaryFB
                                     : Japandi.Colors.textTertiaryFB)
                Text(folder.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { folder.isEnabled },
                set: { registry.setEnabled(folder.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(folder.isEnabled ? "Watching" : "Paused")
            .accessibilityLabel(folder.isEnabled ? "Pause folder" : "Resume folder")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")

            Button {
                removeTarget = folder
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Japandi.Colors.warmFallback)
            }
            .buttonStyle(.plain)
            .help("Stop watching folder")
            .accessibilityLabel("Remove folder")
        }
        .padding(.horizontal, Japandi.Spacing.sm)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                pickFolder()
            } label: {
                Label("Add folder…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Japandi.Colors.accentFallback)
            .controlSize(.regular)
            Spacer()
            if !registry.folders.isEmpty {
                Text("\(registry.folders.filter(\.isEnabled).count) of \(registry.folders.count) watching")
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to watch"
        panel.message = "ATHENS will auto-import documents added to this folder."
        panel.prompt = "Watch this folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try registry.addFolder(url)
        } catch {
            NSSound.beep()
        }
    }
}
