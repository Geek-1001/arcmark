# Quick Start: Adding Icons and Images

This is a quick reference for adding assets to Arcmark. For detailed specifications, see [ASSETS.md](ASSETS.md).

## 1. App Icon

### Quick Setup (PNG)

```bash
# 1. Place your 1024x1024px PNG icon
cp /path/to/your-icon.png Resources/AppIcon.png

# 2. Update Bundler.toml
# Add this line under [apps.Arcmark]:
icon = 'Resources/AppIcon.png'

# 3. Rebuild
./scripts/build.sh
```

### Production Setup (ICNS)

```bash
# 1. Convert PNG to ICNS
./scripts/create-icns.sh Resources/AppIcon.png

# 2. Update Bundler.toml
# Change the icon line to:
icon = 'Resources/AppIcon.icns'

# 3. Rebuild
./scripts/build.sh
```

**Icon Requirements:**
- ✅ 1024x1024 pixels
- ✅ PNG or ICNS format
- ✅ sRGB color space
- ✅ Works on light and dark backgrounds

## 2. DMG Background (Optional)

### Quick Setup

```bash
# 1. Place your 600x400px background image
cp /path/to/background.png Resources/dmg-background.png

# 2. Build DMG (it will automatically use the background)
./scripts/build.sh --dmg
```

**Background Requirements:**
- ✅ 600x400 pixels (3:2 aspect ratio)
- ✅ PNG format with transparency
- ✅ Leave space at (125, 150) and (375, 150) for icons
- ⚠️ Optional - DMG works without it

## 3. Verify Your Assets

### Check Icon

```bash
# Build and open the app
./scripts/build.sh
open .build/bundler/

# Right-click Arcmark.app → Get Info to see the icon
```

### Check DMG

```bash
# Build DMG and open it
./scripts/build.sh --dmg
open .build/dmg/Arcmark-0.1.0.dmg

# Verify the background appears in the Finder window
```

## Common Issues

### Icon Not Showing?

```bash
# Clean build and clear icon cache
./scripts/clean.sh
./scripts/build.sh
sudo rm -rf /Library/Caches/com.apple.iconservices.store
killall Finder
```

### Wrong Icon Size?

```bash
# Check your PNG dimensions
sips -g pixelWidth -g pixelHeight Resources/AppIcon.png

# Should output:
#   pixelWidth: 1024
#   pixelHeight: 1024
```

### DMG Background Not Working?

The script will skip the background if the file is missing - this is normal and the DMG will still work. If you have the file but it's not showing:

```bash
# Check file exists and has correct dimensions
ls -lh Resources/dmg-background.png
sips -g pixelWidth -g pixelHeight Resources/dmg-background.png

# Should output:
#   pixelWidth: 600
#   pixelHeight: 400
```

## File Structure

```
arcmark/
├── Resources/
│   ├── AppIcon.png          # Your 1024x1024 app icon
│   ├── AppIcon.icns         # (Optional) Native macOS icon
│   └── dmg-background.png   # (Optional) 600x400 DMG background
├── Bundler.toml             # Update icon = 'Resources/AppIcon.png'
└── scripts/
    ├── build.sh             # Build app (add --dmg for DMG)
    └── create-icns.sh       # Convert PNG to ICNS
```

## Design Tools

### Creating App Icons

- **Figma**: [figma.com](https://figma.com) - Free design tool
- **Sketch**: [sketch.com](https://sketch.com) - Mac-native (paid)
- **Icon templates**: Search for "macOS icon template" on Figma Community
- **AI generation**: Try DALL-E, Midjourney, or Stable Diffusion

### Creating DMG Backgrounds

- **Figma**: Create 600x400 frame, export as PNG
- **Canva**: [canva.com](https://canva.com) - Free online tool
- **Pixelmator**: Native Mac app (paid)
- **GIMP**: [gimp.org](https://gimp.org) - Free alternative to Photoshop

## Example Bundler.toml

```toml
format_version = 2

[apps.Arcmark]
identifier = 'com.arcmark.app'
product = 'Arcmark'
version = '0.1.0'
description = 'A workspace-based bookmark manager for macOS'
license = 'MIT'
category = 'public.app-category.productivity'
icon = 'Resources/AppIcon.icns'  # <-- Add this line

[apps.Arcmark.plist]
CFBundleIdentifier = 'com.arcmark.app'
```

## Next Steps

1. ✅ Add app icon
2. ✅ Build and verify icon shows up
3. ⏭️ (Optional) Add DMG background
4. ⏭️ (Optional) Convert to ICNS for production
5. ⏭️ Build DMG for distribution

For detailed specifications and design guidelines, see [ASSETS.md](ASSETS.md).
