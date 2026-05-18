#!/usr/bin/env bash
#
# Re-sign the bundled `llama.xcframework` so the embedded
# `llama.framework` carries a proper signature + correct bundle
# identifier instead of the upstream ad-hoc / `stripped_lib` linker
# signature that ships with prebuilt llama.cpp artifacts.
#
# Why this exists: MAS / notarization validation rejects embedded
# frameworks whose `codesign -dvv` reports either `adhoc` or an
# identifier mismatch with the bundle's `Info.plist`. The upstream
# llama.cpp release pipeline ships exactly that shape, so we have to
# re-sign locally before archive.
#
# Usage:
#   ./Tools/resign-llama-framework.sh
#
# Requires:
#   - One Apple Development or Developer ID Application certificate
#     in the login keychain (the script picks the first match).
#   - `codesign` available on PATH (macOS default).
#
# Re-run whenever you bump the llama.xcframework prebuilt artifact.

set -euo pipefail

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/llama.xcframework"
TARGET_BUNDLE_ID="org.ggml.llama"

if [[ ! -d "$FRAMEWORK_DIR" ]]; then
    echo "error: llama.xcframework not found at $FRAMEWORK_DIR" >&2
    exit 1
fi

# Pick the first available code-signing identity by SHA-1 hash.
# Using the hash (rather than the display name) avoids ambiguity when
# two certs in the keychain share the same Common Name — `codesign`
# bails with "ambiguous" if you pass it the string-name in that case.
# Preference order: Apple Development → Developer ID Application.
IDENTITY_HASH=$(security find-identity -p codesigning -v \
    | grep -E "(Apple Development|Developer ID Application)" \
    | head -1 \
    | awk '{print $2}')

if [[ -z "$IDENTITY_HASH" ]]; then
    echo "error: no Apple Development or Developer ID signing identity found in keychain" >&2
    echo "       run \`security find-identity -p codesigning -v\` to see what's available" >&2
    exit 1
fi

IDENTITY_NAME=$(security find-identity -p codesigning -v \
    | grep "$IDENTITY_HASH" \
    | sed -E 's/.*"([^"]+)".*/\1/')

echo "signing identity: $IDENTITY_NAME ($IDENTITY_HASH)"

# Re-sign each embedded framework slice inside the xcframework. The
# xcframework structure groups platform slices (macos-arm64_x86_64,
# ios-arm64, etc.) — sign whichever ones are present.
for slice in "$FRAMEWORK_DIR"/*/llama.framework; do
    [[ -d "$slice" ]] || continue
    echo "→ signing $slice"
    codesign \
        --force \
        --sign "$IDENTITY_HASH" \
        --identifier "$TARGET_BUNDLE_ID" \
        --options runtime \
        --timestamp=none \
        "$slice"
done

echo
echo "verifying:"
for slice in "$FRAMEWORK_DIR"/*/llama.framework; do
    [[ -d "$slice" ]] || continue
    echo "—"
    codesign -dvv "$slice" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier|Format"
done

echo
echo "done. Clean build folder in Xcode (⇧⌘K) before the next archive."
