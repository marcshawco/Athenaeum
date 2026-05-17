import SwiftUI
import SwiftData

// MARK: - FolderEditorSheet
//
// Create / rename / recolor a `Folder`. Called from:
//   - SidebarView's "+ New folder…" affordance (folder == nil)
//   - SidebarView's right-click "Rename…" on an existing folder
//
// We deliberately keep this small: name field + color swatches. Membership
// is managed elsewhere (right-click "Add to Folder" on documents).

struct FolderEditorSheet: View {
    @Environment(\.modelContext) private var modelContext

    /// nil = create flow, non-nil = edit flow.
    let folder: Folder?
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var colorHex: String = Folder.defaultColors[0]

    var body: some View {
        VStack(alignment: .leading, spacing: Japandi.Spacing.md) {
            Text(folder == nil ? "New folder" : "Edit folder")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Name")
                TextField("Receipts, Medical, Tokyo Trip…", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Color")
                HStack(spacing: 10) {
                    ForEach(Folder.defaultColors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: UInt(hex, radix: 16) ?? 0xB98A4F))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            colorHex == hex
                                                ? Japandi.Colors.textPrimaryFB
                                                : Japandi.Colors.borderFallback,
                                            lineWidth: colorHex == hex ? 2 : 0.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().foregroundStyle(Japandi.Colors.borderFallback)

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .keyboardShortcut(.cancelAction)
                Button(folder == nil ? "Create" : "Save") { commit() }
                    .buttonStyle(.borderedProminent)
                    .tint(Japandi.Colors.accentFallback)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Japandi.Spacing.lg)
        .frame(width: 360)
        .onAppear {
            if let folder {
                name = folder.name
                colorHex = folder.colorHex
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Japandi.Colors.textTertiaryFB)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let folder {
            folder.name = trimmed
            folder.colorHex = colorHex
            folder.modifiedAt = .now
        } else {
            let new = Folder(name: trimmed, colorHex: colorHex)
            modelContext.insert(new)
        }
        modelContext.persist(context: "folder-editor")
        onDismiss()
    }
}
