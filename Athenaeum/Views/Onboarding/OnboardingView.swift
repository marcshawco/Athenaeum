import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            // Pages
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                modelsPage.tag(1)
                importPage.tag(2)
                readyPage.tag(3)
            }
            .tabViewStyle(.automatic)

            Rectangle()
                .fill(Japandi.Colors.borderFallback.opacity(0.8))
                .frame(height: 0.5)

            // Navigation
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation(Japandi.Motion.gentle) { currentPage -= 1 }
                    }
                    .buttonStyle(.plain)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                }

                Spacer()

                // Page dots
                HStack(spacing: Japandi.Spacing.xs) {
                    ForEach(0..<4, id: \.self) { page in
                        Circle()
                            .fill(page == currentPage
                                  ? Japandi.Colors.accentFallback
                                  : Japandi.Colors.borderFallback)
                            .frame(width: 5, height: 5)
                            .animation(Japandi.Motion.snappy, value: currentPage)
                    }
                }

                Spacer()

                if currentPage < 3 {
                    Button("Next") {
                        withAnimation(Japandi.Motion.gentle) { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Japandi.Colors.accentFallback)
                } else {
                    Button("Get Started") {
                        hasCompleted = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Japandi.Colors.accentFallback)
                }
            }
            .padding(Japandi.Spacing.lg)
        }
        .frame(width: 560, height: 480)
        .background(Japandi.Colors.bgFallback)
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: Japandi.Spacing.xl) {
            Spacer()

            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)

            VStack(spacing: Japandi.Spacing.xxs) {
                Text("Athenaeum")
                    .font(.system(size: 34, weight: .light, design: .serif))
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                Text("A private archive")
                    .font(.system(size: 12))
                    .tracking(0.3)
                    .foregroundStyle(Japandi.Colors.textTertiaryFB)
                    .padding(.bottom, Japandi.Spacing.xs)

                Text("Your private, AI-powered document library.\nEverything runs locally on your Mac.")
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Japandi.Spacing.xl) {
                FeatureItem(icon: "lock.shield", title: "Private", description: "No cloud, no tracking")
                FeatureItem(icon: "cpu", title: "Local AI", description: "On-device processing")
                FeatureItem(icon: "tag", title: "Smart Tags", description: "Auto-classification")
            }

            Spacer()
        }
        .padding(Japandi.Spacing.lg)
    }

    // MARK: - Models

    private var modelsPage: some View {
        VStack(spacing: Japandi.Spacing.lg) {
            Spacer()

            Image(systemName: "cpu")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.accentMutedFallback)

            VStack(spacing: Japandi.Spacing.sm) {
                Text("Local AI Models")
                    .font(Japandi.Typography.title)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                Text("Athenaeum uses three specialised models")
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            }

            VStack(spacing: Japandi.Spacing.sm) {
                ModelInfoRow(
                    name: "Qwen 2.5 14B",
                    role: "Tagging + Chat",
                    size: "~9.0 GB",
                    color: Japandi.Colors.accentFallback
                )
                ModelInfoRow(
                    name: "Nomic Embed v1.5",
                    role: "Retrieval Embeddings",
                    size: "~84 MB",
                    color: Japandi.Colors.warmFallback
                )
                ModelInfoRow(
                    name: "MiniCPM-V",
                    role: "Smart OCR",
                    size: "~5.0 GB",
                    color: Japandi.Colors.mineralFallback
                )
            }
            .padding(Japandi.Spacing.md)
            .premiumPane()

            Text("Download models from Model Status after setup.\nYou can import documents without models installed.")
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Japandi.Spacing.lg)
    }

    // MARK: - Import

    private var importPage: some View {
        VStack(spacing: Japandi.Spacing.lg) {
            Spacer()

            Image(systemName: "arrow.down.doc")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.accentFallback)

            VStack(spacing: Japandi.Spacing.sm) {
                Text("Import Documents")
                    .font(Japandi.Typography.title)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                Text("Drag files in, use the import button, or place documents in your local vault folder")
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Japandi.Spacing.sm) {
                FormatRow(icon: "doc.richtext",  label: "PDF documents",      ext: ".pdf")
                FormatRow(icon: "doc.text",       label: "Word documents",     ext: ".docx")
                FormatRow(icon: "doc.plaintext",  label: "Text files",         ext: ".txt, .rtf")
                FormatRow(icon: "photo",          label: "Images (with OCR)", ext: ".png, .jpg, .tiff")
            }
            .padding(Japandi.Spacing.md)
            .frame(maxWidth: 320)
            .premiumPane()

            Spacer()
        }
        .padding(Japandi.Spacing.lg)
    }

    // MARK: - Ready

    private var readyPage: some View {
        VStack(spacing: Japandi.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Japandi.Colors.accentFallback.opacity(0.08))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(Japandi.Colors.accentFallback.opacity(0.2), lineWidth: 0.5)
                    .frame(width: 96, height: 96)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(Japandi.Colors.accentFallback)
            }

            VStack(spacing: Japandi.Spacing.sm) {
                Text("You're All Set")
                    .font(Japandi.Typography.largeTitle)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)

                Text("Start building your document library.\nAthenaeum will handle the rest.")
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Japandi.Spacing.xs) {
                KeyboardHint(keys: "⌘ I", action: "Import documents")
                KeyboardHint(keys: "⌘ F", action: "Search library")
                KeyboardHint(keys: "⌘ ,", action: "Settings")
            }

            Spacer()
        }
        .padding(Japandi.Spacing.lg)
    }
}

// MARK: - Supporting Views

private struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: Japandi.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.accentMutedFallback)

            Text(title)
                .font(Japandi.Typography.headline)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            Text(description)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
        .frame(width: 120)
    }
}

private struct ModelInfoRow: View {
    let name: String
    let role: String
    let size: String
    let color: Color

    var body: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Japandi.Typography.body)
                    .foregroundStyle(Japandi.Colors.textPrimaryFB)
                Text(role)
                    .font(Japandi.Typography.caption)
                    .foregroundStyle(Japandi.Colors.textSecondaryFB)
            }

            Spacer()

            Text(size)
                .font(Japandi.Typography.caption)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
    }
}

private struct FormatRow: View {
    let icon: String
    let label: String
    let ext: String

    var body: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .ultraLight))
                .foregroundStyle(Japandi.Colors.accentMutedFallback)
                .frame(width: 22)

            Text(label)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)

            Spacer()

            Text(ext)
                .font(Japandi.Typography.mono)
                .foregroundStyle(Japandi.Colors.textTertiaryFB)
        }
    }
}

private struct KeyboardHint: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: Japandi.Spacing.sm) {
            Text(keys)
                .font(Japandi.Typography.mono)
                .foregroundStyle(Japandi.Colors.textPrimaryFB)
                .padding(.horizontal, Japandi.Spacing.xs)
                .padding(.vertical, 3)
                .background(Japandi.Colors.surfaceFallback)
                .clipShape(RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Japandi.Radius.sm, style: .continuous)
                        .strokeBorder(Japandi.Colors.borderFallback.opacity(0.85), lineWidth: 0.5)
                )

            Text(action)
                .font(Japandi.Typography.body)
                .foregroundStyle(Japandi.Colors.textSecondaryFB)
        }
    }
}
