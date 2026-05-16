#!/bin/bash
# bump-build.sh — Auto-increment CURRENT_PROJECT_VERSION on every source file edit.
# MARKETING_VERSION patch is bumped here too; Claude bumps major manually for big changes.

PBXPROJ="/Users/astral/Documents/[02] Development/Athenaeum/Athenaeum.xcodeproj/project.pbxproj"

# Read the file being edited from hook stdin JSON
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Only fire for files inside the Athenaeum project
[[ "$FILE" == *"Documents/[02] Development/Athenaeum/Athenaeum"* ]] || exit 0

# Never bump when editing the pbxproj itself — would recurse
[[ "$FILE" == *"project.pbxproj"* ]] && exit 0

# Never bump when editing this script or settings
[[ "$FILE" == *".claude/"* ]] && exit 0

# ── Build number (CURRENT_PROJECT_VERSION) ──────────────────────────────────
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | grep -oE '[0-9]+' | head -1)
[[ -z "$BUILD" ]] && exit 0
NEW_BUILD=$((BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = ${BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# ── Marketing version patch bump (x.y.z → x.y.z+1) ─────────────────────────
VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -n "$VERSION" ]]; then
  MAJOR=$(echo "$VERSION" | cut -d. -f1)
  MINOR=$(echo "$VERSION" | cut -d. -f2)
  PATCH=$(echo "$VERSION" | cut -d. -f3)
  NEW_PATCH=$((PATCH + 1))
  NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
  sed -i '' "s/MARKETING_VERSION = ${VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"
fi

exit 0
