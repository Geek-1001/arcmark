# Arcmark Architecture

**Last Updated:** 2026-02-10
**Status:** Post-Refactoring (All 5 Phases Complete)

## Overview

Arcmark is a macOS bookmark management application built with Swift and AppKit. It uses a workspace-based organization system with hierarchical folders and links, featuring drag-and-drop, inline editing, and automatic favicon/title fetching.

## Architecture Patterns

### 1. Unidirectional Data Flow

```
User Action → MainViewController → AppModel → AppState → DataStore → Disk
                     ↑                                        ↓
                     └──────── onChange callback ─────────────┘
```

- **AppModel**: Single source of truth, owns AppState
- **AppState**: Immutable data model (Codable)
- **DataStore**: Persistence layer (JSON + favicon storage)
- **MainViewController**: UI coordinator, observes AppModel via onChange callback

### 2. Component Architecture (Post-Refactoring)

**Base Classes** eliminate code duplication:
- `BaseControl`: Interactive controls with hover + pressed states (~40 lines saved per subclass)
- `BaseView`: Non-interactive views with hover state only (~40 lines saved per subclass)
- `InlineEditableTextField`: Reusable inline editing component (~80 lines saved per usage)

**Design System** ensures consistency:
- `ThemeConstants`: Centralized colors, fonts, spacing, opacity, animations
- Replaces 50+ hardcoded "magic numbers" throughout codebase

## Project Structure

```
Sources/ArcmarkCore/
├── Components/
│   ├── Base/
│   │   ├── BaseControl.swift          # Base for interactive controls
│   │   ├── BaseView.swift             # Base for custom views
│   │   └── InlineEditableTextField.swift
│   ├── Buttons/
│   │   ├── IconTitleButton.swift      # Extends BaseControl
│   │   ├── CustomTextButton.swift     # Extends BaseControl
│   │   └── CustomToggle.swift         # Extends BaseControl
│   ├── Lists/
│   │   ├── NodeRowView.swift          # Extends BaseView
│   │   ├── WorkspaceRowView.swift     # Extends BaseView
│   │   └── ... (collection view items, layout)
│   ├── Inputs/
│   │   └── SearchBarView.swift
│   └── Navigation/
│       └── WorkspaceSwitcherView.swift
├── ViewControllers/
│   ├── MainViewController.swift       # Main coordinator (596 lines, down from 1352)
│   ├── NodeListViewController.swift   # Manages collection view (~800 lines)
│   ├── SearchCoordinator.swift        # Handles search/filtering (~65 lines)
│   └── ... (preferences, settings)
├── Models/
│   ├── Models.swift                   # AppState, Workspace, Node (Link/Folder)
│   ├── WorkspaceColor.swift
│   └── SidebarPosition.swift
├── State/
│   ├── AppModel.swift                 # Central state manager
│   └── DataStore.swift                # Persistence layer
├── Services/
│   ├── FaviconService.swift           # Async favicon fetching
│   ├── LinkTitleService.swift         # HTML title extraction
│   ├── BrowserManager.swift           # Browser selection & URL opening
│   └── ... (window attachment, Arc import)
└── Utilities/
    ├── NodeFiltering.swift            # Recursive filtering
    └── Theme/
        └── ThemeConstants.swift       # Design system constants
```

## Core Data Model

```swift
AppState                      // Root container
├── workspaces: [Workspace]
└── selectedWorkspaceId: UUID?

Workspace                     // Named container
├── id: UUID
├── name: String
├── emoji: String
├── color: WorkspaceColorId
└── items: [Node]             // Root-level items

Node                          // Recursive tree structure
├── .folder(Folder)
│   ├── id: UUID
│   ├── name: String
│   ├── isExpanded: Bool
│   └── children: [Node]      // Nested items
└── .link(Link)
    ├── id: UUID
    ├── title: String
    ├── url: URL
    └── faviconPath: String?
```

## Key Design Decisions

### State Management
- **All mutations through AppModel methods** - no direct state access
- **Automatic persistence** - DataStore saves after every mutation
- **Observer pattern** - onChange callback for UI updates
- **Recursive tree operations** - insertNode, updateNode, removeNode, findNodeLocation

### UI Updates
- **Collection view animations** - calculated diffs for smooth insertions/deletions
- **Inline rename pattern** - scheduled via `pendingInlineRenameId`, executed after data reload
- **Hover state management** - centralized in base classes, no duplicate tracking area code
- **Design consistency** - all components use ThemeConstants for colors/fonts/spacing

### ViewController Decomposition (Phase 3)
- **MainViewController** (596 lines) - Coordinator between search, list, and settings
- **NodeListViewController** (~800 lines) - Collection view, drag-drop, context menus
- **SearchCoordinator** (~65 lines) - Search/filtering logic
- **WorkspaceManagementView** (~380 lines) - Settings workspace management

## Component Patterns

### Creating Interactive Controls

```swift
final class MyButton: BaseControl {
    override func handleHoverStateChanged() {
        layer?.backgroundColor = isHovered
            ? ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
            : NSColor.clear.cgColor
    }

    override func handlePressedStateChanged() {
        // Update appearance based on isPressed
    }
}
```

### Creating Custom Views

```swift
final class MyRowView: BaseView {
    override func handleHoverStateChanged() {
        // Update appearance based on isHovered
    }
}
```

### Using ThemeConstants

```swift
// Colors
layer?.backgroundColor = ThemeConstants.Colors.darkGray.cgColor

// With opacity
let hoverColor = ThemeConstants.Colors.darkGray
    .withAlphaComponent(ThemeConstants.Opacity.minimal)

// Fonts
label.font = ThemeConstants.Fonts.bodyRegular

// Spacing
stackView.spacing = ThemeConstants.Spacing.regular

// Animation
CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
```

## Testing Strategy

- **Model tests** - JSON round-trip, move operations, filtering
- **ThemeConstants tests** - Validates all design values (16 tests)
- **Base class tests** - Currently skipped (Swift 6 concurrency + XCTest issues)
- **Total: 20 tests** - All passing, zero failures

## Refactoring Impact (2026-02-10)

**Code Reduction:**
- Eliminated 1,145 lines of duplicate code (14.1% reduction)
- MainViewController: 1352 → 596 lines (56% reduction)

**Improvements:**
- Zero functional regressions
- Centralized design system (ThemeConstants)
- Eliminated 6+ instances of duplicate hover state logic
- Eliminated 3+ instances of duplicate inline editing logic
- Consistent component patterns across all UI

**Documentation:**
- 900+ lines of comprehensive inline documentation
- Component usage guide (400+ lines)
- Architecture and refactoring history documented

## Dependencies

- **Swift 6** with strict concurrency
- **AppKit** for macOS UI
- **Swift Bundler** for app bundle creation
- No external dependencies for core functionality

## Build System

```bash
# Build app bundle
./scripts/build.sh

# Build and run
./scripts/run.sh

# Run tests
swift test
```

See [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md) for details on build process and code signing.

## Future Considerations

**Optional Enhancements:**
- Folder structure reorganization (move files into categorized subdirectories)
- Visual regression testing suite
- Async XCTest infrastructure for base class tests
- Performance benchmarking and profiling
- Memory leak testing with Instruments

**Architecture is Stable:**
- All 5 refactoring phases complete
- Production-ready with comprehensive documentation
- Ready for new feature development

## Resources

- [CLAUDE.md](../CLAUDE.md) - Detailed development guide
- [REFACTORING_PLAN.md](REFACTORING_PLAN.md) - Complete refactoring history
- [COMPONENT_USAGE_GUIDE.md](COMPONENT_USAGE_GUIDE.md) - Component usage patterns
- [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md) - Build system details
