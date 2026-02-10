#!/bin/bash
# Build Arcmark as a proper macOS app bundle
#
# Usage:
#   ./scripts/build.sh           # Build app only
#   ./scripts/build.sh --dmg     # Build app and create DMG

set -e  # Exit on error

# Parse arguments
CREATE_DMG=false
if [ "$1" = "--dmg" ]; then
    CREATE_DMG=true
fi

echo "🔨 Building Arcmark..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Read version from VERSION file and update Bundler.toml
if [ -f "VERSION" ]; then
    VERSION=$(cat VERSION | tr -d '[:space:]')
    echo "📌 Version: $VERSION"

    # Update version in Bundler.toml if it differs
    if grep -q "^version = " Bundler.toml; then
        CURRENT_VERSION=$(grep "^version = " Bundler.toml | head -1 | sed "s/version = '\(.*\)'/\1/" | tr -d "'")
        if [ "$CURRENT_VERSION" != "$VERSION" ]; then
            echo "  → Updating Bundler.toml version to $VERSION"
            sed -i '' "s/^version = .*/version = '$VERSION'/" Bundler.toml
        fi
    fi
fi

# Build the app bundle using swift-bundler
mint run swift-bundler bundle -c release

# Post-build: Patch Info.plist with CFBundleIdentifier
# Swift Bundler v2.0.7 has an issue where [apps.*.plist] values don't always merge
echo "🔧 Patching Info.plist..."
INFO_PLIST=".build/bundler/Arcmark.app/Contents/Info.plist"

# Add CFBundleIdentifier if missing (using PlistBuddy)
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string 'com.arcmark.app'" "$INFO_PLIST"
    echo "  ✓ Added CFBundleIdentifier"
else
    # Update if already exists but has wrong value
    CURRENT_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
    if [ "$CURRENT_ID" != "com.arcmark.app" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier 'com.arcmark.app'" "$INFO_PLIST"
        echo "  ✓ Updated CFBundleIdentifier"
    else
        echo "  ✓ CFBundleIdentifier already correct"
    fi
fi

# Code sign the app with ad-hoc signature
echo "🔏 Code signing app..."
codesign --force --deep --sign - ".build/bundler/Arcmark.app" 2>&1 | grep -v "replacing existing signature" || true

# Verify the build
echo ""
echo "✅ Build complete!"
echo "📦 App bundle: .build/bundler/Arcmark.app"
echo ""
echo "🔍 Verification:"
echo "  Bundle ID: $(defaults read "$(pwd)/$INFO_PLIST" CFBundleIdentifier 2>/dev/null || echo 'ERROR: Not found')"
echo "  Version: $(defaults read "$(pwd)/$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo 'Not set')"
echo "  Code Sign: $(codesign -dvv ".build/bundler/Arcmark.app" 2>&1 | grep "^Identifier=" | cut -d= -f2)"

# Create DMG if requested
if [ "$CREATE_DMG" = true ]; then
    echo ""
    echo "────────────────────────────────────────"
    ./scripts/create-dmg.sh
fi
