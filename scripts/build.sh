#!/bin/bash
# Build Arcmark as a proper macOS app bundle
#
# Usage:
#   ./scripts/build.sh                  # Build with ad-hoc signing (development)
#   ./scripts/build.sh --dmg            # Build with ad-hoc signing and create DMG
#   ./scripts/build.sh --production     # Build with Developer ID signing (production)
#   ./scripts/build.sh --production --dmg  # Build and create notarized DMG

set -e  # Exit on error

# Parse arguments
CREATE_DMG=false
PRODUCTION=false

for arg in "$@"; do
    case $arg in
        --dmg)
            CREATE_DMG=true
            ;;
        --production)
            PRODUCTION=true
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--production] [--dmg]"
            exit 1
            ;;
    esac
done

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

# Post-build: Ensure Sparkle.framework is embedded
echo "🔧 Checking Sparkle.framework embedding..."
FRAMEWORKS_DIR=".build/bundler/Arcmark.app/Contents/Frameworks"
if [ ! -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    echo "  → Sparkle.framework not found in app bundle, copying..."
    mkdir -p "$FRAMEWORKS_DIR"
    # Find Sparkle.framework in the build artifacts
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
else
    echo "  ✓ Sparkle.framework already embedded"
fi

# Patch Info.plist with Sparkle keys (SUFeedURL, SUPublicEDKey)
echo "🔧 Patching Info.plist with Sparkle keys..."
FEED_URL="https://geek-1001.github.io/arcmark/appcast.xml"

if ! /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string '$FEED_URL'" "$INFO_PLIST"
    echo "  ✓ Added SUFeedURL"
else
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL '$FEED_URL'" "$INFO_PLIST"
    echo "  ✓ Updated SUFeedURL"
fi

if ! /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ''" "$INFO_PLIST"
    echo "  ✓ Added SUPublicEDKey (placeholder - run generate_keys to set)"
else
    echo "  ✓ SUPublicEDKey already present"
fi

# Add @executable_path/../Frameworks to rpath so dyld can find embedded frameworks
echo "🔧 Fixing rpath for embedded frameworks..."
EXECUTABLE=".build/bundler/Arcmark.app/Contents/MacOS/Arcmark"
if ! otool -l "$EXECUTABLE" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$EXECUTABLE"
    echo "  ✓ Added Frameworks rpath"
else
    echo "  ✓ Frameworks rpath already present"
fi

# Code sign the app
echo "🔏 Code signing app..."

if [ "$PRODUCTION" = true ]; then
    # Production signing with Developer ID
    if [ ! -f ".notarization-config" ]; then
        echo "❌ Error: .notarization-config not found"
        echo "   See docs/PRODUCTION_SIGNING.md for setup instructions"
        exit 1
    fi

    # Load signing identity from config
    source .notarization-config

    if [ -z "$SIGNING_IDENTITY" ]; then
        echo "❌ Error: SIGNING_IDENTITY not set in .notarization-config"
        exit 1
    fi

    echo "  → Using Developer ID: $SIGNING_IDENTITY"

    # Sign with hardened runtime for notarization
    codesign --force --deep \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        ".build/bundler/Arcmark.app" 2>&1 | grep -v "replacing existing signature" || true

    echo "  ✓ Signed with Developer ID (hardened runtime enabled)"
else
    # Development signing with ad-hoc signature
    codesign --force --deep --sign - ".build/bundler/Arcmark.app" 2>&1 | grep -v "replacing existing signature" || true
    echo "  ✓ Signed with ad-hoc signature (development only)"
fi

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
    if [ "$PRODUCTION" = true ]; then
        ./scripts/create-dmg.sh --notarize
    else
        ./scripts/create-dmg.sh
    fi
fi
