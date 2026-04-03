import SwiftUI

// MARK: - Brand Colors
//
// Palette: Warm Linen × Forest Green
//
// Background  #F6F5F1  — warm linen; not clinical, not gray
// Surface     #FFFFFF  — pure white cards stand out from the linen field
// Navy        #121212  — near-black chrome; tab bar, avatars, dark elements
// Accent      #1B9966  — forest green; fresh, trusted, money — primary brand color
// Success     #1B9966  — same green (unified, no split identity)
// Warning     #CF8B0E  — dark amber; sophisticated, not traffic-light
// Destructive #C73333  — confident red
// TextSub     #6F6F6F  — neutral mid-gray
// Border      #E6E5E2  — warm hairline; barely visible on linen

extension Color {
    /// Forest green — primary brand color, interactive elements, selected states
    static let sweeplyAccent      = Color(red: 0.106, green: 0.600, blue: 0.400)

    /// Near-black — tab bar, avatar backgrounds, dark emphasis
    static let sweeplyNavy        = Color(red: 0.071, green: 0.071, blue: 0.071)

    /// Warm linen — page background
    static let sweeplyBackground  = Color(red: 0.965, green: 0.961, blue: 0.945)

    /// Forest green — confirmed, paid, completed states (intentionally = accent)
    static let sweeplySuccess     = Color(red: 0.106, green: 0.600, blue: 0.400)

    /// Dark amber — attention, pending, unpaid
    static let sweeplyWarning     = Color(red: 0.812, green: 0.545, blue: 0.055)

    /// Confident red — overdue, error, destructive
    static let sweeplyDestructive = Color(red: 0.780, green: 0.200, blue: 0.200)

    /// Neutral mid-gray — secondary text, captions, placeholders
    static let sweeplyTextSub     = Color(red: 0.435, green: 0.435, blue: 0.435)

    /// Pure white — cards, sheets, input backgrounds
    static let sweeplySurface     = Color.white

    /// Warm hairline — borders, dividers
    static let sweeplyBorder      = Color(red: 0.902, green: 0.898, blue: 0.886)
}

// MARK: - Typography
extension Font {
    static func sweeplyDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func sweeplyMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Spacing
enum Spacing {
    static let xs: CGFloat   = 4
    static let sm: CGFloat   = 8
    static let md: CGFloat   = 12
    static let base: CGFloat = 16
    static let lg: CGFloat   = 20
    static let xl: CGFloat   = 24
    static let xxl: CGFloat  = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius
enum Radius {
    static let sm: CGFloat   = 8
    static let md: CGFloat   = 12
    static let lg: CGFloat   = 16
    static let xl: CGFloat   = 20
    static let full: CGFloat = 999
}
