#!/bin/bash
# Build Arcmark as a proper macOS app bundle

set -e  # Exit on error

echo "🔨 Building Arcmark..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

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
echo "  Code Sign: $(codesign -dvv ".build/bundler/Arcmark.app" 2>&1 | grep "^Identifier=" | cut -d= -f2)"
