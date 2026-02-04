# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Arcmark is a macOS bookmark management application built with Swift and AppKit. It provides a workspace-based organization system for links and folders with features like drag-and-drop, inline editing, and automatic favicon/title fetching.

## Development Commands

**IMPORTANT**: Never run `./scripts/run.sh` or any build/run scripts automatically. The user will run these scripts in the background when needed.

### Building and Testing
```bash
# Build the project
swift build

# Run tests
swift test

# Run a single test
swift test --filter ModelTests.testJSONRoundTrip

# Build for release
swift build -c release
```

## Architecture

### Data Flow Architecture

The application follows a unidirectional data flow pattern:

1. **AppModel** - Central state manager that owns `AppState` and coordinates all mutations
   - Single source of truth for application state
   - Exposes an `onChange` callback for UI updates
   - All state mutations go through AppModel methods (no direct state manipulation)
   - Automatically persists to disk via `DataStore` after every mutation

2. **DataStore** - Handles persistence layer
   - Saves/loads JSON to `~/Library/Application Support/Arcmark/data.json`
   - Manages favicon storage in `Icons/` subdirectory
   - Provides default state initialization

3. **MainViewController** - Primary UI controller
   - Observes AppModel via `onChange` callback
   - Manages NSCollectionView for hierarchical node display
   - Handles drag-and-drop, inline editing, and context menus
   - Never directly mutates state - always calls AppModel methods

### Core Data Model

The data model is defined in `Models.swift`:

- **AppState** - Root container holding workspaces and selected workspace ID
- **Workspace** - Named container with emoji, color, and hierarchical items
- **Node** - Enum representing either a `Folder` or `Link`
  - `Folder` - Contains nested children and isExpanded state
  - `Link` - URL, title, and optional favicon path

All models are Codable and use UUID-based identification. The Node enum uses custom encoding to serialize the tagged union structure.

### Key Components

**Services** (all MainActor singletons):
- **FaviconService** - Async favicon fetching with disk caching and failure cooldown
- **LinkTitleService** - HTML title extraction from URLs
- **BrowserManager** - Manages browser selection and URL opening

**UI Components**:
- **MainViewController** - Collection view-based hierarchical list with animations
- **NodeCollectionViewItem** - Reusable cell with icon, title, hover states, delete button
- **SearchBarView** - Search field that filters nodes
- **IconTitleButton** - Custom button for paste action
- **ListFlowLayout** - Custom NSCollectionViewLayout for vertical list

### State Mutation Pattern

All mutations follow this pattern:
```swift
// 1. Validate preconditions
// 2. Call updateWorkspace or updateNode with closure
// 3. Closure modifies inout parameter
// 4. AppModel automatically persists and notifies observers
```

Examples:
- `addFolder(name:parentId:)` - Inserts new folder node
- `moveNode(id:toParentId:index:)` - Moves node in hierarchy, handles reordering logic
- `renameNode(id:newName:)` - Updates node display name
- `deleteNode(id:)` - Recursively removes node from tree

### Node Hierarchy Operations

The AppModel uses recursive tree traversal for node operations:
- `insertNode(_:parentId:index:nodes:)` - Recursive insertion into parent
- `updateNode(id:nodes:_:)` - Recursive update with mutation closure
- `removeNode(id:nodes:)` - Recursive removal returning deleted node
- `findNodeLocation(id:nodes:parentId:)` - Returns NodeLocation with parent ID and index

When moving nodes, the system:
1. Validates the move isn't to a descendant (prevents cycles)
2. Removes node from old location
3. Adjusts target index if needed (accounts for removal in same parent)
4. Inserts at new location

### UI Update Strategy

**Collection View Animations**:
- Calculates diff between old and new visible rows
- Uses `performBatchUpdates` for insertions/deletions
- Animates inserted rows with fade + slide from offset
- Creates bitmap snapshots for deletion animation
- Skips animations when query is active or window not visible

**Inline Rename**:
- Triggered via context menu or for new folders
- `scheduleInlineRename(for:)` sets `pendingInlineRenameId`
- After data reload, `handlePendingInlineRename()` activates edit mode
- Edit mode managed by NodeCollectionViewItem with commit/cancel callbacks

### Workspace Colors

WorkspaceColorId enum defines 8 color themes (Blush, Apricot, Butter, Leaf, Mint, Sky, Periwinkle, Lavender). Each color affects:
- Window background color (color at 0.92 alpha)
- View layer background color

## Important Patterns

### AppKit-Specific Patterns
- Uses `@MainActor` extensively for UI thread safety
- Custom NSCollectionViewLayout for list metrics
- Context menus via NSMenuDelegate with dynamic population
- Drag-and-drop via NSPasteboardWriting/NSPasteboardReading

### State Management
- Never expose mutable state directly - only through methods
- Use `inout` parameters in private update methods for efficient mutations
- All persistence is automatic - callers never call save()
- Use `notify: false` parameter to suppress onChange callback if needed

### Search/Filter
- NodeFiltering recursively filters tree, expanding folders with matches
- MainViewController forces folder expansion when query is active
- Filtering preserves hierarchy (keeps parent folders if children match)
- The drag and drop is disabled when searching/filtering

### Testing
- Tests use temporary directory for DataStore to avoid polluting real data
- Model operations tested via AppModel integration (not isolated units)
- Tests verify both state mutation and JSON round-trip encoding
