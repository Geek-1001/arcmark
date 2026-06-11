#!/bin/bash
# Quick verification script for Arcmark build
# Usage: ./scripts/verify-build.sh [path-to-app]

APP_PATH="${1:-.build/bundler/Arcmark.app}"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at: $APP_PATH"
    echo "Usage: $0 [path-to-app]"
    exit 1
fi

echo "🔍 Verifying Arcmark build at: $APP_PATH"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Info.plist Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check plist validity
if plutil -lint "$APP_PATH/Contents/Info.plist" > /dev/null 2>&1; then
    echo "✅ Info.plist is valid XML"
else
    echo "❌ Info.plist is malformed"
    exit 1
fi

# Check CFBundleIdentifier
BUNDLE_ID=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
if [ "$BUNDLE_ID" = "com.arcmark.app" ]; then
    echo "✅ CFBundleIdentifier: $BUNDLE_ID"
else
    echo "❌ CFBundleIdentifier: ${BUNDLE_ID:-NOT FOUND} (expected: com.arcmark.app)"
fi

# Check other critical keys
BUNDLE_NAME=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleName 2>/dev/null)
BUNDLE_VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
echo "   CFBundleName: $BUNDLE_NAME"
echo "   CFBundleShortVersionString: $BUNDLE_VERSION"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔏 Code Signature Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check signature details
CODESIGN_OUTPUT=$(codesign -dvv "$APP_PATH" 2>&1)

SIGNATURE_ID=$(echo "$CODESIGN_OUTPUT" | grep "^Identifier=" | cut -d= -f2)
SIGNATURE_FORMAT=$(echo "$CODESIGN_OUTPUT" | grep "^Format=" | cut -d= -f2-)
SIGNATURE_TYPE=$(echo "$CODESIGN_OUTPUT" | grep "^Signature=" | cut -d= -f2)
INFO_PLIST_ENTRIES=$(echo "$CODESIGN_OUTPUT" | grep "^Info.plist entries=" | cut -d= -f2)

if [ "$SIGNATURE_ID" = "com.arcmark.app" ]; then
    echo "✅ Signature Identifier: $SIGNATURE_ID"
else
    echo "❌ Signature Identifier: $SIGNATURE_ID (expected: com.arcmark.app)"
fi

echo "   Format: $SIGNATURE_FORMAT"
echo "   Signature Type: $SIGNATURE_TYPE"
echo "   Info.plist entries: $INFO_PLIST_ENTRIES"

# Verify signature validity
if codesign --verify --verbose=4 "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
    echo "✅ Signature is valid"
elif codesign --verify --verbose=4 "$APP_PATH" > /dev/null 2>&1; then
    echo "✅ Signature is valid"
else
    echo "❌ Signature is invalid or missing"
    codesign --verify --verbose=4 "$APP_PATH"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Bundle Structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check critical files
if [ -f "$APP_PATH/Contents/MacOS/Arcmark" ]; then
    echo "✅ Executable found: Contents/MacOS/Arcmark"
    file "$APP_PATH/Contents/MacOS/Arcmark" | grep -q "Mach-O" && echo "   Architecture: $(file "$APP_PATH/Contents/MacOS/Arcmark" | grep -o 'arm64\|x86_64')"
else
    echo "❌ Executable not found"
fi

if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "✅ Info.plist found"
else
    echo "❌ Info.plist not found"
fi

if [ -d "$APP_PATH/Contents/Resources" ]; then
    echo "✅ Resources directory found"
else
    echo "⚠️  Resources directory not found"
fi

# The bundled note editor must ship at this exact path. If it is missing,
# the notes feature is dead in the field — and historically a missing
# resource bundle crashed the app on launch. Treat its absence as fatal so a
# broken artifact can never be published.
EDITOR_INDEX="$APP_PATH/Contents/Resources/Arcmark_ArcmarkCore.bundle/Contents/Resources/NoteEditor/index.html"
if [ -f "$EDITOR_INDEX" ]; then
    echo "✅ Note editor resources found: Arcmark_ArcmarkCore.bundle/.../NoteEditor/index.html"
    EDITOR_OK=true
else
    echo "❌ Note editor resources missing (expected at $EDITOR_INDEX)"
    EDITOR_OK=false
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$BUNDLE_ID" = "com.arcmark.app" ] && [ "$SIGNATURE_ID" = "com.arcmark.app" ] && [ "$EDITOR_OK" = "true" ]; then
    echo "✅ Build verification PASSED"
    echo ""
    echo "Ready for installation:"
    echo "  cp -R $APP_PATH /Applications/"
    exit 0
else
    echo "❌ Build verification FAILED"
    echo ""
    echo "Please rebuild:"
    echo "  ./scripts/build.sh"
    exit 1
fi
