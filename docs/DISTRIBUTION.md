# Distribution Guide

This document describes how to build and distribute Arcmark for beta testing and release.

**See also:**
- [ASSETS.md](ASSETS.md) - App icon and DMG background specifications
- [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md) - Build system and code signing details

## Version Management

### VERSION File

The project uses a centralized `VERSION` file in the project root to manage the app version. This file contains a single version string following [Semantic Versioning](https://semver.org/):

```
0.1.0
```

**Version Format**: `MAJOR.MINOR.PATCH`
- **MAJOR**: Incompatible API changes or major feature overhauls
- **MINOR**: New features added in a backwards-compatible manner
- **PATCH**: Backwards-compatible bug fixes

### Updating the Version

To update the app version:

1. Edit the `VERSION` file with the new version number:
   ```bash
   echo "0.2.0" > VERSION
   ```

2. The build script will automatically:
   - Read the version from the `VERSION` file
   - Update `Bundler.toml` if the version has changed
   - Apply the version to `CFBundleShortVersionString` and `CFBundleVersion` in Info.plist

### Version Configuration

The version is configured in three places (automatically synchronized):

1. **VERSION file** - Source of truth
2. **Bundler.toml** - Swift Bundler configuration
3. **Info.plist** - Generated during build using `$(VERSION)` variable substitution

## Building for Distribution

### Standard Build (App Bundle Only)

To build the app without creating a DMG:

```bash
./scripts/build.sh
```

This creates: `.build/bundler/Arcmark.app`

### Build with DMG Installer

To build the app and create a DMG installer for distribution:

```bash
./scripts/build.sh --dmg
```

This creates:
- `.build/bundler/Arcmark.app` - The application bundle
- `.build/dmg/Arcmark-X.Y.Z.dmg` - Distributable DMG installer

### DMG Creation Only

If you've already built the app and just want to create a DMG:

```bash
./scripts/create-dmg.sh
```

## DMG Installer Features

The generated DMG includes:

- **Drag-and-Drop Installation**: Users drag Arcmark.app to the Applications folder symlink
- **Professional Layout**: Custom Finder window with icon arrangement
- **Version in Filename**: DMG named `Arcmark-X.Y.Z.dmg` based on VERSION file
- **Compressed Format**: Uses UDZO (zlib compression) for smaller file size
- **Verified Code Signing**: Includes ad-hoc code signature for local development

### DMG Structure

```
Arcmark X.Y.Z/
├── Arcmark.app          # The application bundle
└── Applications/        # Symlink to /Applications
```

When mounted, users see:
- The Arcmark app on the left
- Applications folder shortcut on the right
- Instructions to drag-and-drop

## Distribution Workflow

### For Beta Testing

1. **Update Version** (if needed):
   ```bash
   echo "0.2.0-beta.1" > VERSION
   ```

2. **Build DMG**:
   ```bash
   ./scripts/build.sh --dmg
   ```

3. **Test the DMG**:
   ```bash
   open .build/dmg/Arcmark-0.2.0-beta.1.dmg
   ```

4. **Distribute**:
   - Upload DMG to file sharing service
   - Share download link with beta testers
   - Include installation instructions (see below)

### For Release

1. **Update Version** (remove pre-release suffix):
   ```bash
   echo "1.0.0" > VERSION
   ```

2. **Build Release DMG**:
   ```bash
   ./scripts/build.sh --dmg
   ```

3. **Test Installation**:
   - Mount the DMG
   - Drag to Applications
   - Verify app launches correctly

4. **Create Git Tag**:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

5. **Distribute**:
   - Upload to GitHub Releases
   - Update website download links
   - Announce to users

## Installation Instructions for Users

Share these instructions with beta testers:

### Installing Arcmark

1. **Download** the DMG file (e.g., `Arcmark-0.2.0.dmg`)

2. **Open** the downloaded DMG file by double-clicking it

3. **Drag** the Arcmark icon to the Applications folder icon

4. **Eject** the Arcmark disk image from Finder

5. **Launch** Arcmark from your Applications folder or Spotlight

6. **First Launch**: macOS may show a security prompt since the app isn't notarized yet. Click "Open" to proceed.

### Updating Arcmark

To update to a new version:

1. **Quit** Arcmark if it's running
2. **Download** the new DMG file
3. **Follow** the same installation steps above (this will replace the old version)

## Code Signing Notes

**Current Status**: The app uses ad-hoc code signing (development only).

**For Production**: You'll need to:
1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. Create a Developer ID Application certificate
3. Update `scripts/build.sh` to use your certificate:
   ```bash
   codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" ".build/bundler/Arcmark.app"
   ```
4. Consider adding [notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution) to avoid Gatekeeper warnings

See [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md) for more details on code signing.

## Build Artifacts

### Directory Structure

```
.build/
├── bundler/
│   └── Arcmark.app              # Built application bundle
└── dmg/
    ├── Arcmark-X.Y.Z.dmg        # Distributable DMG
    └── dmg-staging/             # Temporary (cleaned up automatically)
```

### Cleaning Build Artifacts

To remove all build artifacts:

```bash
./scripts/clean.sh
```

This removes the entire `.build/` directory.

## Troubleshooting

### DMG Creation Fails

**Issue**: "Error: App bundle not found"
**Solution**: Run `./scripts/build.sh` first to build the app

**Issue**: Finder window customization doesn't work
**Solution**: The DMG will still be created and functional, just without custom layout

### Version Not Updating

**Issue**: Info.plist shows old version
**Solution**: Clean build and rebuild:
```bash
./scripts/clean.sh
./scripts/build.sh
```

### Code Signing Errors

**Issue**: "resource fork, Finder information, or similar detritus not allowed"
**Solution**: The build script handles this automatically with `--force --deep` flags

## Future Improvements

- [ ] Automated notarization for production releases
- [ ] Custom DMG background image
- [ ] Sparkle framework integration for auto-updates
- [ ] CI/CD pipeline for automated builds
- [ ] TestFlight-style beta distribution portal
