import SwiftUI

// MARK: - Brand Colors
//
// Palette: Warm Linen × Forest Green
//
// ┌─────────────────────────────────────────────────────────────┐
// │  Color discipline — read before using any sweeply* color    │
// │                                                             │
// │  PRIMARY TEXT → Color.primary (system black)                │
// │  SECONDARY TEXT → sweeplyTextSub (gray)                     │
// │  NUMBERS & AMOUNTS → Color.primary — never colored          │
// │  BACKGROUNDS → sweeplyBackground (pages) / sweeplySurface   │
// │                                                             │
// │  sweeplyAccent:      CTA buttons · selected tabs · checkmarks│
// │  sweeplySuccess:     "Paid" badge only                      │
// │  sweeplyWarning:     "Unpaid" badge only                    │
// │  sweeplyDestructive: "Overdue" badge · destructive actions  │
// │                                                             │
// │  ⚠️  Never use accent/success/warning on body text,         │
// │     stat numbers, icons, or decorative elements.            │
// └─────────────────────────────────────────────────────────────┘

extension Color {
    /// Forest green — CTA buttons, selected state, checkmarks, "Paid" badge
    static let sweeplyAccent      = Color(red: 0.106, green: 0.600, blue: 0.400)

    /// Near-black — tab bar, avatar fill, dark UI chrome
    static let sweeplyNavy        = Color(red: 0.071, green: 0.071, blue: 0.071)

    /// Warm linen — page/scroll background
    static let sweeplyBackground  = Color(red: 0.965, green: 0.961, blue: 0.945)

    /// Forest green — "Paid" confirmed states (= accent, unified)
    static let sweeplySuccess     = Color(red: 0.106, green: 0.600, blue: 0.400)

    /// Dark amber — "Unpaid" badge only
    static let sweeplyWarning     = Color(red: 0.812, green: 0.545, blue: 0.055)

    /// Confident red — "Overdue" badge, error states, destructive actions
    static let sweeplyDestructive = Color(red: 0.780, green: 0.200, blue: 0.200)

    /// Mid-gray — secondary labels, captions, placeholder text, section headers
    static let sweeplyTextSub     = Color(red: 0.435, green: 0.435, blue: 0.435)

    /// Pure white — card and sheet backgrounds
    static let sweeplySurface     = Color.white

    /// Warm hairline — borders, dividers, separators
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
