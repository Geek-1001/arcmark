# Component Usage Guide

This guide provides practical examples for using Arcmark's base classes and design system components.

## Table of Contents
1. [ThemeConstants](#themeconstants)
2. [BaseControl](#basecontrol)
3. [BaseView](#baseview)
4. [InlineEditableTextField](#inlineeditabletextfield)
5. [Common Patterns](#common-patterns)

---

## ThemeConstants

`ThemeConstants` provides a centralized design system for consistent styling across the application.

### Basic Usage

```swift
import AppKit

// Using colors
layer?.backgroundColor = ThemeConstants.Colors.darkGray.cgColor

// Using colors with opacity
let hoverColor = ThemeConstants.Colors.darkGray
    .withAlphaComponent(ThemeConstants.Opacity.minimal)

// Using fonts
label.font = ThemeConstants.Fonts.bodyRegular
titleLabel.font = ThemeConstants.Fonts.bodySemibold

// Using spacing
stackView.spacing = ThemeConstants.Spacing.regular
view.layoutMargins = NSEdgeInsets(
    top: ThemeConstants.Spacing.large,
    left: ThemeConstants.Spacing.extraLarge,
    bottom: ThemeConstants.Spacing.large,
    right: ThemeConstants.Spacing.extraLarge
)

// Using corner radius
layer?.cornerRadius = ThemeConstants.CornerRadius.medium

// Using sizing
imageView.frame.size = CGSize(
    width: ThemeConstants.Sizing.iconMedium,
    height: ThemeConstants.Sizing.iconMedium
)

// Using animation values
CATransaction.begin()
CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)
layer?.opacity = 0.5
CATransaction.commit()
```

### Creating Custom Fonts

```swift
// For custom sizes while maintaining consistency
let largeTitle = ThemeConstants.Fonts.systemFont(size: 18, weight: .semibold)
let smallCaption = ThemeConstants.Fonts.systemFont(size: 12, weight: .regular)
```

### Opacity Levels Quick Reference

```swift
// Full opacity - No transparency
ThemeConstants.Opacity.full        // 1.0

// High opacity - Primary content with slight transparency
ThemeConstants.Opacity.high         // 0.8

// Medium opacity - Secondary content
ThemeConstants.Opacity.medium       // 0.6

// Low opacity - Tertiary content or disabled states
ThemeConstants.Opacity.low          // 0.4

// Subtle opacity - Selected or focused backgrounds
ThemeConstants.Opacity.subtle       // 0.15

// Extra subtle - Very light backgrounds
ThemeConstants.Opacity.extraSubtle  // 0.10

// Minimal - Hover states with barely visible tint
ThemeConstants.Opacity.minimal      // 0.06
```

---

## BaseControl

`BaseControl` is a base class for interactive controls (buttons, toggles) with automatic hover and pressed state management.

### Creating a Custom Button

```swift
import AppKit

final class MyCustomButton: BaseControl {

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Setup your subviews
        titleLabel.font = ThemeConstants.Fonts.bodyMedium
        titleLabel.textColor = ThemeConstants.Colors.white

        addSubview(iconView)
        addSubview(titleLabel)

        // ... layout code

        updateAppearance()
    }

    // Override to respond to hover state changes
    override func handleHoverStateChanged() {
        updateAppearance()
    }

    // Override to respond to pressed state changes
    override func handlePressedStateChanged() {
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundOpacity: CGFloat
        let textOpacity: CGFloat

        if isPressed {
            backgroundOpacity = ThemeConstants.Opacity.subtle
            textOpacity = ThemeConstants.Opacity.high
        } else if isHovered {
            backgroundOpacity = ThemeConstants.Opacity.minimal
            textOpacity = ThemeConstants.Opacity.full
        } else {
            backgroundOpacity = 0
            textOpacity = ThemeConstants.Opacity.high
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
        CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)

        layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(backgroundOpacity).cgColor
        titleLabel.alphaValue = textOpacity

        CATransaction.commit()
    }

    // Optional: Override to customize action behavior
    override func performAction() {
        // Custom action logic
        print("Button clicked!")

        // Still send the action to target
        super.performAction()
    }
}
```

### Using the Custom Button

```swift
let button = MyCustomButton(frame: .zero)
button.target = self
button.action = #selector(handleButtonClick)

// BaseControl automatically handles:
// - Hover state detection
// - Pressed state tracking
// - Mouse event handling
// - Tracking area management
```

---

## BaseView

`BaseView` is a base class for non-interactive custom views that need hover state detection (like row views in lists).

### Creating a Custom Row View

```swift
import AppKit

final class MyCustomRow: BaseView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var isSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        titleLabel.font = ThemeConstants.Fonts.bodyMedium
        titleLabel.textColor = ThemeConstants.Colors.darkGray

        subtitleLabel.font = ThemeConstants.Fonts.bodyRegular
        subtitleLabel.textColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.medium)

        addSubview(titleLabel)
        addSubview(subtitleLabel)

        // ... layout code

        updateVisualState()
    }

    // Override to respond to hover state changes
    override func handleHoverStateChanged() {
        updateVisualState()
    }

    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        updateVisualState()
    }

    private func updateVisualState() {
        let backgroundColor: NSColor

        if isSelected {
            backgroundColor = ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.subtle)
        } else if isHovered {
            backgroundColor = ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.minimal)
        } else {
            backgroundColor = .clear
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
        layer?.backgroundColor = backgroundColor.cgColor
        CATransaction.commit()
    }
}
```

### BaseView vs BaseControl - When to Use Which?

**Use BaseControl when:**
- Creating interactive controls (buttons, toggles, sliders)
- Need both hover AND pressed state tracking
- Want automatic mouse tracking loop
- Control should perform an action on click

**Use BaseView when:**
- Creating non-interactive views (row views, cards, containers)
- Only need hover state detection (no pressed state)
- View doesn't perform actions directly
- Simpler than BaseControl for display-only components

---

## InlineEditableTextField

`InlineEditableTextField` provides reusable inline text editing with commit/cancel functionality.

### Basic Usage

```swift
import AppKit

final class MyEditableCard: NSView {

    private let editableTitle = InlineEditableTextField()
    private let editButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Configure the editable text field
        editableTitle.text = "Initial Title"
        editableTitle.font = ThemeConstants.Fonts.bodyMedium
        editableTitle.textColor = ThemeConstants.Colors.darkGray

        addSubview(editableTitle)
        addSubview(editButton)

        editButton.target = self
        editButton.action = #selector(startEditing)

        // ... layout code
    }

    @objc private func startEditing() {
        editableTitle.beginInlineRename(
            onCommit: { [weak self] newText in
                // User pressed Enter with valid text
                self?.handleTitleChanged(newText)
            },
            onCancel: { [weak self] in
                // User pressed Escape or focus was lost
                print("Edit canceled")
            }
        )
    }

    private func handleTitleChanged(_ newTitle: String) {
        print("Title changed to: \(newTitle)")
        // Update your model, persist changes, etc.
    }
}
```

### Integration with Row Views

```swift
final class EditableRowView: BaseView {

    private let editableTitle = InlineEditableTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        editableTitle.font = ThemeConstants.Fonts.bodyRegular
        editableTitle.textColor = ThemeConstants.Colors.white
        addSubview(editableTitle)

        // ... layout code
    }

    // Public method to trigger inline editing
    func beginRename(currentTitle: String, onCommit: @escaping (String) -> Void) {
        editableTitle.text = currentTitle
        editableTitle.beginInlineRename(
            onCommit: onCommit,
            onCancel: {
                print("Rename canceled")
            }
        )
    }

    // Public method to check if currently editing
    var isEditing: Bool {
        editableTitle.isEditing
    }

    // Public method to programmatically cancel editing
    func cancelEditing() {
        editableTitle.cancelInlineRename()
    }
}
```

### Edit Behavior Details

**Commit triggers (calls onCommit):**
- User presses Enter key
- Text is non-empty after trimming whitespace

**Cancel triggers (calls onCancel):**
- User presses Escape key
- Text field loses focus (click outside)
- Text is empty after trimming whitespace

**Automatic features:**
- Text is selected when editing begins
- Original text is restored on cancel
- Whitespace is trimmed on commit
- Focus management is automatic

---

## Common Patterns

### Pattern 1: Hover State with Animation

```swift
override func handleHoverStateChanged() {
    CATransaction.begin()
    CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
    CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)

    if isHovered {
        layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
    } else {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    CATransaction.commit()
}
```

### Pattern 2: Multi-State Appearance (Pressed, Hovered, Default)

```swift
private func updateAppearance() {
    let opacity: CGFloat

    if isPressed {
        opacity = ThemeConstants.Opacity.subtle
    } else if isHovered {
        opacity = ThemeConstants.Opacity.minimal
    } else {
        opacity = 0
    }

    CATransaction.begin()
    CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
    layer?.backgroundColor = ThemeConstants.Colors.darkGray
        .withAlphaComponent(opacity).cgColor
    CATransaction.commit()
}
```

### Pattern 3: Custom Style Struct with ThemeConstants

```swift
struct MyButtonStyle {
    let backgroundColor: NSColor
    let textColor: NSColor
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat

    static let primary = MyButtonStyle(
        backgroundColor: ThemeConstants.Colors.darkGray,
        textColor: ThemeConstants.Colors.white,
        hoverOpacity: ThemeConstants.Opacity.minimal,
        pressedOpacity: ThemeConstants.Opacity.subtle
    )

    static let secondary = MyButtonStyle(
        backgroundColor: ThemeConstants.Colors.settingsBackground,
        textColor: ThemeConstants.Colors.darkGray,
        hoverOpacity: ThemeConstants.Opacity.extraSubtle,
        pressedOpacity: ThemeConstants.Opacity.subtle
    )
}
```

### Pattern 4: Programmatic Hover State Refresh

```swift
// After dynamically changing view hierarchy or bounds
override func layout() {
    super.layout()
    // BaseControl/BaseView automatically call refreshHoverState()
}

// Manual refresh if needed (e.g., after modal dismissal)
myButton.refreshHoverState()
```

### Pattern 5: Inline Editing with Validation

```swift
func beginRename() {
    editableTextField.beginInlineRename(
        onCommit: { [weak self] newText in
            guard let self = self else { return }

            // Validate the new text
            if self.isValidTitle(newText) {
                self.updateTitle(newText)
            } else {
                self.showValidationError()
                // Optionally start editing again
                self.beginRename()
            }
        },
        onCancel: {
            print("Edit canceled")
        }
    )
}

private func isValidTitle(_ title: String) -> Bool {
    // Your validation logic
    return !title.isEmpty && title.count <= 100
}
```

---

## Migration Guide: From Old Pattern to New Pattern

### Before: Manual Hover State Management

```swift
// OLD - Don't do this anymore
final class OldButton: NSControl {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        // ... appearance logic
    }
}
```

### After: Using BaseControl

```swift
// NEW - Much cleaner!
final class NewButton: BaseControl {
    override func handleHoverStateChanged() {
        updateAppearance()
    }

    private func updateAppearance() {
        // isHovered is automatically managed by BaseControl
        layer?.backgroundColor = isHovered
            ? ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
            : NSColor.clear.cgColor
    }
}
```

### Before: Hardcoded Constants

```swift
// OLD - Don't do this anymore
let color = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)
let opacity: CGFloat = 0.8
let font = NSFont.systemFont(ofSize: 14, weight: .regular)
let spacing: CGFloat = 10
let cornerRadius: CGFloat = 8
```

### After: Using ThemeConstants

```swift
// NEW - Centralized and consistent!
let color = ThemeConstants.Colors.darkGray
let opacity = ThemeConstants.Opacity.high
let font = ThemeConstants.Fonts.bodyRegular
let spacing = ThemeConstants.Spacing.regular
let cornerRadius = ThemeConstants.CornerRadius.medium
```

---

## Best Practices

1. **Always use ThemeConstants** instead of hardcoded values for colors, fonts, spacing, etc.
2. **Prefer BaseControl over manual tracking area setup** for interactive controls
3. **Use BaseView for display-only components** that need hover state
4. **Leverage InlineEditableTextField** instead of reimplementing inline editing
5. **Animate state changes** using ThemeConstants.Animation values for consistency
6. **Use semantic opacity names** (minimal, subtle, etc.) instead of raw numbers
7. **Document custom override behavior** when extending base classes
8. **Keep appearance logic in dedicated methods** (e.g., `updateAppearance()`)

---

## Additional Resources

- See [REFACTORING_PLAN.md](/REFACTORING_PLAN.md) for the full refactoring history
- See [CLAUDE.md](/CLAUDE.md) for architecture overview
- Check the source code for `BaseControl`, `BaseView`, and `InlineEditableTextField` for implementation details
- Look at existing components like `IconTitleButton`, `NodeRowView`, and `WorkspaceRowView` for real-world examples
