import XCTest
@testable import ArcmarkCore

@MainActor
final class ThemeConstantsTests: XCTestCase {

    // MARK: - Color Tests

    func testColorsAreValid() {
        // Verify colors have valid RGB values (0-1 range)
        XCTAssertNotNil(ThemeConstants.Colors.darkGray)
        XCTAssertNotNil(ThemeConstants.Colors.white)
        XCTAssertNotNil(ThemeConstants.Colors.settingsBackground)
    }

    func testDarkGrayColor() {
        let color = ThemeConstants.Colors.darkGray
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.078, accuracy: 0.001)
        XCTAssertEqual(green, 0.078, accuracy: 0.001)
        XCTAssertEqual(blue, 0.078, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)
    }

    // MARK: - Opacity Tests

    func testOpacityValuesInValidRange() {
        // All opacity values should be between 0 and 1
        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.full, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.full, 1)

        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.high, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.high, 1)

        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.medium, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.medium, 1)

        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.low, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.low, 1)

        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.subtle, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.subtle, 1)

        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.extraSubtle, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.extraSubtle, 1)

        XCTAssertGreaterThanOrEqual(ThemeConstants.Opacity.minimal, 0)
        XCTAssertLessThanOrEqual(ThemeConstants.Opacity.minimal, 1)
    }

    func testOpacityValuesOrdered() {
        // Verify opacity values are in descending order
        XCTAssertGreaterThan(ThemeConstants.Opacity.full, ThemeConstants.Opacity.high)
        XCTAssertGreaterThan(ThemeConstants.Opacity.high, ThemeConstants.Opacity.medium)
        XCTAssertGreaterThan(ThemeConstants.Opacity.medium, ThemeConstants.Opacity.low)
        XCTAssertGreaterThan(ThemeConstants.Opacity.low, ThemeConstants.Opacity.subtle)
        XCTAssertGreaterThan(ThemeConstants.Opacity.subtle, ThemeConstants.Opacity.extraSubtle)
        XCTAssertGreaterThan(ThemeConstants.Opacity.extraSubtle, ThemeConstants.Opacity.minimal)
    }

    // MARK: - Font Tests

    func testFontsAreSystemAvailable() {
        XCTAssertNotNil(ThemeConstants.Fonts.bodyRegular)
        XCTAssertNotNil(ThemeConstants.Fonts.bodySemibold)
        XCTAssertNotNil(ThemeConstants.Fonts.bodyMedium)
        XCTAssertNotNil(ThemeConstants.Fonts.bodyBold)

        XCTAssertEqual(ThemeConstants.Fonts.bodyRegular.pointSize, 14)
        XCTAssertEqual(ThemeConstants.Fonts.bodySemibold.pointSize, 14)
        XCTAssertEqual(ThemeConstants.Fonts.bodyMedium.pointSize, 14)
        XCTAssertEqual(ThemeConstants.Fonts.bodyBold.pointSize, 14)
    }

    func testSystemFontFunction() {
        let customFont = ThemeConstants.Fonts.systemFont(size: 16, weight: .light)
        XCTAssertNotNil(customFont)
        XCTAssertEqual(customFont.pointSize, 16)
    }

    // MARK: - Spacing Tests

    func testSpacingValuesArePositive() {
        XCTAssertGreaterThan(ThemeConstants.Spacing.tiny, 0)
        XCTAssertGreaterThan(ThemeConstants.Spacing.small, 0)
        XCTAssertGreaterThan(ThemeConstants.Spacing.medium, 0)
        XCTAssertGreaterThan(ThemeConstants.Spacing.regular, 0)
        XCTAssertGreaterThan(ThemeConstants.Spacing.large, 0)
        XCTAssertGreaterThan(ThemeConstants.Spacing.extraLarge, 0)
        XCTAssertGreaterThan(ThemeConstants.Spacing.huge, 0)
    }

    func testSpacingValuesOrdered() {
        // Verify spacing values are in ascending order
        XCTAssertLessThan(ThemeConstants.Spacing.tiny, ThemeConstants.Spacing.small)
        XCTAssertLessThan(ThemeConstants.Spacing.small, ThemeConstants.Spacing.medium)
        XCTAssertLessThan(ThemeConstants.Spacing.medium, ThemeConstants.Spacing.regular)
        XCTAssertLessThan(ThemeConstants.Spacing.regular, ThemeConstants.Spacing.large)
        XCTAssertLessThan(ThemeConstants.Spacing.large, ThemeConstants.Spacing.extraLarge)
        XCTAssertLessThan(ThemeConstants.Spacing.extraLarge, ThemeConstants.Spacing.huge)
    }

    // MARK: - Corner Radius Tests

    func testCornerRadiusValuesArePositive() {
        XCTAssertGreaterThan(ThemeConstants.CornerRadius.small, 0)
        XCTAssertGreaterThan(ThemeConstants.CornerRadius.medium, 0)
        XCTAssertGreaterThan(ThemeConstants.CornerRadius.large, 0)
    }

    func testCornerRadiusRoundFunction() {
        XCTAssertEqual(ThemeConstants.CornerRadius.round(100), 50)
        XCTAssertEqual(ThemeConstants.CornerRadius.round(50), 25)
        XCTAssertEqual(ThemeConstants.CornerRadius.round(20), 10)
    }

    // MARK: - Sizing Tests

    func testIconSizesArePositive() {
        XCTAssertGreaterThan(ThemeConstants.Sizing.iconSmall, 0)
        XCTAssertGreaterThan(ThemeConstants.Sizing.iconMedium, 0)
        XCTAssertGreaterThan(ThemeConstants.Sizing.iconLarge, 0)
        XCTAssertGreaterThan(ThemeConstants.Sizing.iconExtraLarge, 0)
    }

    func testIconSizesOrdered() {
        XCTAssertLessThan(ThemeConstants.Sizing.iconSmall, ThemeConstants.Sizing.iconMedium)
        XCTAssertLessThan(ThemeConstants.Sizing.iconMedium, ThemeConstants.Sizing.iconLarge)
        XCTAssertLessThan(ThemeConstants.Sizing.iconLarge, ThemeConstants.Sizing.iconExtraLarge)
    }

    func testButtonAndRowSizes() {
        XCTAssertGreaterThan(ThemeConstants.Sizing.buttonHeight, 0)
        XCTAssertGreaterThan(ThemeConstants.Sizing.rowHeight, 0)
    }

    // MARK: - Animation Tests

    func testAnimationDurationsArePositive() {
        XCTAssertGreaterThan(ThemeConstants.Animation.durationFast, 0)
        XCTAssertGreaterThan(ThemeConstants.Animation.durationNormal, 0)
        XCTAssertGreaterThan(ThemeConstants.Animation.durationSlow, 0)
    }

    func testAnimationDurationsOrdered() {
        XCTAssertLessThan(ThemeConstants.Animation.durationFast, ThemeConstants.Animation.durationNormal)
        XCTAssertLessThan(ThemeConstants.Animation.durationNormal, ThemeConstants.Animation.durationSlow)
    }

    func testAnimationTimingFunction() {
        XCTAssertNotNil(ThemeConstants.Animation.timingFunction)
    }
}
