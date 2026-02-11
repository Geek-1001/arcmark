# Distribution Guide

This document describes how to build and distribute Arcmark for beta testing and release.

**See also:**
- [ASSETS.md](ASSETS.md) - App icon and DMG background specifications
- [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md) - Build system and code signing details
- [PRODUCTION_SIGNING.md](PRODUCTION_SIGNING.md) - Production code signing and notarization setup

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

### Development Builds (Ad-hoc Signing)

For local testing and early development:

```bash
# Build app only
./scripts/build.sh

# Build app and create DMG
./scripts/build.sh --dmg
```

**Note**: These builds use ad-hoc signing. Users will see security warnings when launching.

### Production Builds (Developer ID + Notarization)

For distribution to beta testers and public release:

**First-time setup** (one-time):
1. Follow the guide in [PRODUCTION_SIGNING.md](PRODUCTION_SIGNING.md)
2. Create your `.notarization-config` file with credentials

**Build commands**:
```bash
# Build with Developer ID signing (no DMG)
./scripts/build.sh --production

# Build and create fully notarized DMG (recommended)
./scripts/build.sh --production --dmg
```

**What happens with `--production --dmg`**:
1. App is built and signed with your Developer ID certificate
2. Hardened runtime is enabled for notarization
3. DMG is created with the signed app
4. DMG is submitted to Apple for notarization (~2-5 minutes)
5. Notarization ticket is stapled to the DMG
6. Result: DMG launches without security warnings ✨

### Build Comparison

| Build Type | Command | Code Signing | Notarization | User Experience |
|------------|---------|--------------|--------------|-----------------|
| Development | `./scripts/build.sh` | Ad-hoc | No | Security warnings |
| Development DMG | `./scripts/build.sh --dmg` | Ad-hoc | No | Security warnings |
| Production | `./scripts/build.sh --production` | Developer ID | No | Click-through warning |
| Production DMG | `./scripts/build.sh --production --dmg` | Developer ID | Yes | No warnings! ✨ |

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

## Code Signing

### Development Signing (Default)

By default, builds use ad-hoc signing for local development:
- No Apple Developer account required
- Fast builds
- ⚠️ Users see security warnings

### Production Signing (Recommended for Distribution)

For production distribution with no security warnings:

**Requirements**:
- Apple Developer Program membership ($99/year)
- Developer ID Application certificate
- App-specific password for notarization

**Setup**: Follow the step-by-step guide in [PRODUCTION_SIGNING.md](PRODUCTION_SIGNING.md)

**Build**: Use `./scripts/build.sh --production --dmg`

**Benefits**:
- ✅ No security warnings for users
- ✅ Professional appearance
- ✅ Required for public distribution
- ✅ Builds trust with users

See [PRODUCTION_SIGNING.md](PRODUCTION_SIGNING.md) for complete setup instructions.

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
