import AppKit

/// Centralized design system constants for Arcmark
struct ThemeConstants {

    // MARK: - Colors

    struct Colors {
        /// Primary dark color #141414
        static let darkGray = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)

        /// Pure white
        static let white = NSColor.white

        /// Settings background #E5E7EB
        static let settingsBackground = NSColor(calibratedRed: 0.898, green: 0.906, blue: 0.922, alpha: 1.0)
    }

    // MARK: - Opacity

    struct Opacity {
        static let full: CGFloat = 1.0
        static let high: CGFloat = 0.8
        static let medium: CGFloat = 0.6
        static let low: CGFloat = 0.4
        static let subtle: CGFloat = 0.15
        static let extraSubtle: CGFloat = 0.10
        static let minimal: CGFloat = 0.06
    }

    // MARK: - Typography

    @MainActor
    struct Fonts {
        static let bodyRegular = NSFont.systemFont(ofSize: 14, weight: .regular)
        static let bodySemibold = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let bodyMedium = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let bodyBold = NSFont.systemFont(ofSize: 14, weight: .bold)

        static func systemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - Spacing

    struct Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let regular: CGFloat = 10
        static let large: CGFloat = 14
        static let extraLarge: CGFloat = 16
        static let huge: CGFloat = 20
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static func round(_ value: CGFloat) -> CGFloat { value / 2 }
    }

    // MARK: - Sizing

    struct Sizing {
        static let iconSmall: CGFloat = 14
        static let iconMedium: CGFloat = 18
        static let iconLarge: CGFloat = 22
        static let iconExtraLarge: CGFloat = 26

        static let buttonHeight: CGFloat = 32
        static let rowHeight: CGFloat = 44
    }

    // MARK: - Animation

    @MainActor
    struct Animation {
        static let durationFast: TimeInterval = 0.15
        static let durationNormal: TimeInterval = 0.2
        static let durationSlow: TimeInterval = 0.3

        static let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }
}
