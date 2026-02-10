import AppKit

/// Centralized design system constants for Arcmark.
///
/// `ThemeConstants` provides a single source of truth for all design values used throughout
/// the application. This ensures consistency and makes it easy to update the visual design
/// from a single location.
///
/// ## Structure
/// Constants are organized into nested structs by category:
/// - **Colors**: Brand colors and semantic color values
/// - **Opacity**: Standard opacity levels for layering and states
/// - **Fonts**: Typography with consistent sizing and weights
/// - **Spacing**: Standard spacing values for layout consistency
/// - **CornerRadius**: Rounding values for UI elements
/// - **Sizing**: Standard sizes for icons, buttons, and rows
/// - **Animation**: Timing values for smooth transitions
///
/// ## Usage
/// ```swift
/// // Colors
/// layer?.backgroundColor = ThemeConstants.Colors.darkGray.cgColor
///
/// // With opacity
/// let hoverColor = ThemeConstants.Colors.darkGray
///     .withAlphaComponent(ThemeConstants.Opacity.minimal)
///
/// // Typography
/// textField.font = ThemeConstants.Fonts.bodyRegular
///
/// // Spacing and sizing
/// stackView.spacing = ThemeConstants.Spacing.regular
/// imageView.frame.size = CGSize(
///     width: ThemeConstants.Sizing.iconMedium,
///     height: ThemeConstants.Sizing.iconMedium
/// )
///
/// // Animation
/// CATransaction.begin()
/// CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
/// CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)
/// // ... animations
/// CATransaction.commit()
/// ```
///
/// ## Design Philosophy
/// - Use semantic names that describe purpose, not specific values
/// - Provide a progression of values (e.g., tiny → small → medium → large)
/// - Avoid magic numbers scattered throughout the codebase
/// - Make global design changes from a single file
struct ThemeConstants {

    // MARK: - Colors

    /// Standard color palette for the application.
    struct Colors {
        /// Primary dark color used for text, icons, and UI elements.
        /// Hex: #141414 | RGB: (20, 20, 20)
        static let darkGray = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)

        /// Pure white used for light text and icons on dark backgrounds.
        static let white = NSColor.white

        /// Light gray background used in settings and preferences views.
        /// Hex: #E5E7EB | RGB: (229, 231, 235)
        static let settingsBackground = NSColor(calibratedRed: 0.898, green: 0.906, blue: 0.922, alpha: 1.0)
    }

    // MARK: - Opacity

    /// Standard opacity levels for layering, hover states, and visual hierarchy.
    ///
    /// Use these constants with `NSColor.withAlphaComponent(_:)` to create
    /// semi-transparent colors with consistent opacity levels.
    ///
    /// Example:
    /// ```swift
    /// let hoverBackground = ThemeConstants.Colors.darkGray
    ///     .withAlphaComponent(ThemeConstants.Opacity.minimal)
    /// ```
    struct Opacity {
        /// Fully opaque (1.0) - No transparency
        static let full: CGFloat = 1.0

        /// High opacity (0.8) - Primary content with slight transparency
        static let high: CGFloat = 0.8

        /// Medium opacity (0.6) - Secondary content
        static let medium: CGFloat = 0.6

        /// Low opacity (0.4) - Tertiary content or disabled states
        static let low: CGFloat = 0.4

        /// Subtle opacity (0.15) - Selected or focused backgrounds
        static let subtle: CGFloat = 0.15

        /// Extra subtle opacity (0.10) - Very light backgrounds
        static let extraSubtle: CGFloat = 0.10

        /// Minimal opacity (0.06) - Hover states with barely visible tint
        static let minimal: CGFloat = 0.06
    }

    // MARK: - Typography

    /// Standard typography styles for text throughout the application.
    ///
    /// All fonts use the system font (San Francisco on macOS) at size 14 with varying weights.
    /// For custom sizes or weights, use the `systemFont(size:weight:)` helper function.
    ///
    /// Example:
    /// ```swift
    /// // Standard body text
    /// label.font = ThemeConstants.Fonts.bodyRegular
    ///
    /// // Custom size and weight
    /// titleLabel.font = ThemeConstants.Fonts.systemFont(size: 18, weight: .semibold)
    /// ```
    struct Fonts {
        /// Body text with regular weight (size 14, weight: regular)
        nonisolated(unsafe) static let bodyRegular = NSFont.systemFont(ofSize: 14, weight: .regular)

        /// Body text with semibold weight (size 14, weight: semibold) - Good for emphasis
        nonisolated(unsafe) static let bodySemibold = NSFont.systemFont(ofSize: 14, weight: .semibold)

        /// Body text with medium weight (size 14, weight: medium) - Subtle emphasis
        nonisolated(unsafe) static let bodyMedium = NSFont.systemFont(ofSize: 14, weight: .medium)

        /// Body text with bold weight (size 14, weight: bold) - Strong emphasis
        nonisolated(unsafe) static let bodyBold = NSFont.systemFont(ofSize: 14, weight: .bold)

        /// Creates a system font with custom size and weight.
        ///
        /// - Parameters:
        ///   - size: The point size of the font
        ///   - weight: The weight of the font (e.g., .regular, .semibold, .bold)
        /// - Returns: A system font with the specified size and weight
        static func systemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - Spacing

    /// Standard spacing values for consistent layout and padding.
    ///
    /// Use these values for margins, padding, gaps between elements, and insets.
    /// Following an 8-point grid system (with some exceptions) for visual consistency.
    ///
    /// Example:
    /// ```swift
    /// stackView.spacing = ThemeConstants.Spacing.regular
    /// view.layoutMargins = NSEdgeInsets(
    ///     top: ThemeConstants.Spacing.large,
    ///     left: ThemeConstants.Spacing.extraLarge,
    ///     bottom: ThemeConstants.Spacing.large,
    ///     right: ThemeConstants.Spacing.extraLarge
    /// )
    /// ```
    struct Spacing {
        /// Tiny spacing (4pt) - Minimal gaps within compact components
        static let tiny: CGFloat = 4

        /// Small spacing (6pt) - Tight spacing for related elements
        static let small: CGFloat = 6

        /// Medium spacing (8pt) - Standard spacing within components
        static let medium: CGFloat = 8

        /// Regular spacing (10pt) - Default spacing between elements
        static let regular: CGFloat = 10

        /// Large spacing (14pt) - Comfortable spacing between groups
        static let large: CGFloat = 14

        /// Extra large spacing (16pt) - Generous spacing for major sections
        static let extraLarge: CGFloat = 16

        /// Huge spacing (20pt) - Maximum spacing for clear separation
        static let huge: CGFloat = 20
    }

    // MARK: - Corner Radius

    /// Standard corner radius values for rounded UI elements.
    ///
    /// Use these values to maintain consistent rounding throughout the application.
    ///
    /// Example:
    /// ```swift
    /// layer?.cornerRadius = ThemeConstants.CornerRadius.medium
    ///
    /// // For perfect circles
    /// layer?.cornerRadius = ThemeConstants.CornerRadius.round(view.bounds.height)
    /// ```
    struct CornerRadius {
        /// Small radius (6pt) - Subtle rounding for small elements
        static let small: CGFloat = 6

        /// Medium radius (8pt) - Standard rounding for buttons and cards
        static let medium: CGFloat = 8

        /// Large radius (12pt) - Prominent rounding for larger elements
        static let large: CGFloat = 12

        /// Creates a perfectly round corner radius (half of the value).
        ///
        /// - Parameter value: The dimension (width or height) to make round
        /// - Returns: Half of the input value for perfect circular rounding
        static func round(_ value: CGFloat) -> CGFloat { value / 2 }
    }

    // MARK: - Sizing

    /// Standard sizing values for UI elements.
    ///
    /// Use these values to ensure consistent sizing of icons, buttons, and rows.
    ///
    /// Example:
    /// ```swift
    /// imageView.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)?
    ///     .withSymbolConfiguration(.init(pointSize: ThemeConstants.Sizing.iconMedium, weight: .regular))
    ///
    /// button.heightAnchor.constraint(equalToConstant: ThemeConstants.Sizing.buttonHeight).isActive = true
    /// ```
    struct Sizing {
        /// Small icon size (14pt) - Compact icons for inline use
        static let iconSmall: CGFloat = 14

        /// Medium icon size (18pt) - Standard icon size for most UI
        static let iconMedium: CGFloat = 18

        /// Large icon size (22pt) - Prominent icons for primary actions
        static let iconLarge: CGFloat = 22

        /// Extra large icon size (26pt) - Large icons for emphasis
        static let iconExtraLarge: CGFloat = 26

        /// Standard button height (32pt)
        static let buttonHeight: CGFloat = 32

        /// Standard row height (44pt) - For list and table rows
        static let rowHeight: CGFloat = 44
    }

    // MARK: - Animation

    /// Standard animation timing values for smooth transitions.
    ///
    /// Use these values with CATransaction or NSAnimationContext for consistent animations.
    ///
    /// Example:
    /// ```swift
    /// CATransaction.begin()
    /// CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
    /// CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)
    /// layer?.opacity = 0.5
    /// CATransaction.commit()
    /// ```
    struct Animation {
        /// Fast animation duration (0.15s) - Quick feedback for hover states
        static let durationFast: TimeInterval = 0.15

        /// Normal animation duration (0.2s) - Standard transitions
        static let durationNormal: TimeInterval = 0.2

        /// Slow animation duration (0.3s) - Deliberate, noticeable animations
        static let durationSlow: TimeInterval = 0.3

        /// Standard easing function for smooth, natural motion.
        /// Uses ease-in-ease-out timing (slow start, fast middle, slow end).
        nonisolated(unsafe) static let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }
}
