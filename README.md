<picture>
  <img src="./Resources/AppIcon.png" width="96" style="filter: drop-shadow(0 2px 6px rgba(0, 0, 0, 0.18));">
</picture>

# Arcmark

<p align="center">
  <img src="resources/screenshots/screenshot-1-app.png" alt="Arcmark main window" width="100%">
</p>

Arcmark is a native macOS bookmark manager built with Swift and AppKit that attaches to any browser window as a sidebar. 
Inspired fully by how the tabs organization works in Arc browser's sidebar, so that the author could finally stop using this browser and try something else.

## Demo

!TODO: Add demo video

## Why Arcmark?

**Browser-Attached Sidebar** - Float alongside any browser window (Chrome, Arc, Safari, Brave, etc.) for instant access to your bookmarks without switching apps.

**Workspace Organization** - Organize bookmarks into multiple workspaces with custom window colors. Create nested folder hierarchies with drag-and-drop.

**Local-first** - All bookmarks stored in a single JSON file (`~/Library/Application Support/Arcmark/data.json`).

## Features

### Browser Integration
- **Sidebar Attachment** - Automatically attaches to browser windows and follows them across spaces. If you prefer, you can still use Arcmark as a standalone bookmark manager window, not attaching it anywhere.
- **Supported Browsers** - Chrome, Arc, Safari, Brave, etc.
- **Always-on-Top Mode** - Pin Arcmark window to stay visible on top of all apps.
- **Arc Import** - Import links (aka pinned tabs) directly from Arc browser via settings.

### Organization
- **Multiple Workspaces** - Separate bookmark collections with custom-colored workspaces.
- **Nested Folders** - Create hierarchical folder structures for your links.
- **Drag-and-Drop** - Reorder and move bookmarks between folders and workspaces
- **Inline Editing** - Rename folders and links directly in the list
- **Search & Filter** - Quickly find bookmarks in any workspace

<p align="center">
  <img src="resources/screenshots/screenshot-2-settings.png" alt="Arcmark settings" width="100%">
</p>

## Download

**Latest Release**: [Download Arcmark v0.1.0](../../releases/latest)

### System Requirements
- macOS 13.0 or later
- Accessibility permissions (required for browser window attachment); Not needed if you intend to use it as a standalone window.

## Installation

1. Download the latest `.dmg` file from the [Releases](../../releases) page
2. Open the downloaded DMG file
3. Drag **Arcmark.app** to your **Applications** folder

![Installation](resources/screenshots/screenshot-3-dmg.png)

4. Launch Arcmark from your Applications folder

## Setup

### Accessibility Permissions

For the sidebar attachment feature to work, grant Arcmark accessibility permissions:

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the **+** button and add **Arcmark.app**
3. Enable the checkbox next to Arcmark

Without this permission, the app will function as a standalone bookmark manager but won't attach to browser windows. The app will prompt to grant accessibility permission if the "Attach to window as sidebar" option is selected.

### Importing from Arc

To import bookmarks from Arc browser:

1. Open Arcmark settings (⌘,)
2. Click **Import Bookmarks** and select your Arc export file

Arc stores your workspace locally in `~/Library/Application Support/Arc/StorableSidebar.json`. Arcmark parses this file to recreate exactly the same folder and spaces structure you've had previously.

## Building from Source

### Prerequisites

- macOS 13.0 or later
- Swift 6.2 or later
- [swift-bundler](https://github.com/stackotter/swift-bundler)

### Install swift-bundler

```bash
mint install stackotter/swift-bundler@main
```

Or follow instructions at [swiftbundler.dev](https://swiftbundler.dev).

### Build and Run

```bash
git clone https://github.com/yourusername/arcmark.git
cd arcmark

# Build and run
./scripts/run.sh

# Build only (creates .build/bundler/Arcmark.app)
./scripts/build.sh

# Create DMG installer
./scripts/build.sh --dmg
```

The app is built to `.build/bundler/Arcmark.app` and can be run directly:
```bash
open .build/bundler/Arcmark.app
```

## Contributing
For bug reports, please [open an issue](#).

For other changes, feel free to a open pull requests. See [CLAUDE.md](CLAUDE.md) and `docs/` for architecture details, development guidelines, and build instructions.

## License

MIT License - see [LICENSE](LICENSE) for details
