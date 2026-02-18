#!/bin/bash
# Build and run Arcmark as a proper macOS app bundle

set -e  # Exit on error

echo "🚀 Building and running Arcmark..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Build using swift-bundler (debug mode)
mint run swift-bundler bundle

# Post-build: Ensure Sparkle.framework is embedded
FRAMEWORKS_DIR=".build/bundler/Arcmark.app/Contents/Frameworks"
if [ ! -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    echo "🔧 Embedding Sparkle.framework..."
    mkdir -p "$FRAMEWORKS_DIR"
    SPARKLE_FW=$(find .build -path "*/artifacts/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" -type d 2>/dev/null | head -1)
    if [ -z "$SPARKLE_FW" ]; then
        SPARKLE_FW=$(find .build -name "Sparkle.framework" -path "*/Sparkle.xcframework/*" -type d 2>/dev/null | head -1)
    fi
    if [ -n "$SPARKLE_FW" ]; then
        cp -R "$SPARKLE_FW" "$FRAMEWORKS_DIR/"
        echo "  ✓ Copied Sparkle.framework"
    else
        echo "  ⚠️  Warning: Could not find Sparkle.framework in build artifacts"
    fi
fi

# Post-build: Patch Info.plist (Swift Bundler doesn't always merge plist values)
INFO_PLIST=".build/bundler/Arcmark.app/Contents/Info.plist"
VERSION=$(cat VERSION | tr -d '[:space:]')

# Patch version strings (required by Sparkle)
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string '$VERSION'" "$INFO_PLIST"
else
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$VERSION'" "$INFO_PLIST"
fi
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string '$VERSION'" "$INFO_PLIST"
else
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion '$VERSION'" "$INFO_PLIST"
fi

# Patch CFBundleIdentifier
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string 'com.arcmark.app'" "$INFO_PLIST"
fi

# Add @executable_path/../Frameworks to rpath so dyld can find embedded frameworks
EXECUTABLE=".build/bundler/Arcmark.app/Contents/MacOS/Arcmark"
if ! otool -l "$EXECUTABLE" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$EXECUTABLE"
    echo "  ✓ Added Frameworks rpath"
fi

# Ad-hoc code sign for development
codesign --force --deep --sign - ".build/bundler/Arcmark.app" 2>&1 | grep -v "replacing existing signature" || true

# Run the app
echo "🚀 Launching Arcmark..."
open ".build/bundler/Arcmark.app"
