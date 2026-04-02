import SwiftUI

// MARK: - Brand Colors
/// Restrained, professional palette — muted tones, no loud accent colors.
extension Color {
    /// Primary interactive / selection (muted blue-slate)
    static let sweeplyAccent = Color(red: 0.32, green: 0.40, blue: 0.48)
    /// Chrome surfaces: tab bar, avatars, strong emphasis
    static let sweeplyNavy = Color(red: 0.12, green: 0.13, blue: 0.15)
    /// Page background (warm neutral)
    static let sweeplyBackground = Color(red: 0.96, green: 0.96, blue: 0.95)
    /// Positive / settled (muted sage)
    static let sweeplySuccess = Color(red: 0.38, green: 0.48, blue: 0.42)
    /// Attention / pending (dusty ochre — not traffic-light amber)
    static let sweeplyWarning = Color(red: 0.52, green: 0.45, blue: 0.38)
    /// Critical / overdue (muted brick)
    static let sweeplyDestructive = Color(red: 0.52, green: 0.36, blue: 0.36)
    /// Secondary labels
    static let sweeplyTextSub = Color(red: 0.45, green: 0.45, blue: 0.46)
    /// Cards and sheets
    static let sweeplySurface = Color.white
    /// Hairlines and dividers
    static let sweeplyBorder = Color(red: 0.88, green: 0.88, blue: 0.87)
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
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let base: CGFloat = 16
    static let lg: CGFloat  = 20
    static let xl: CGFloat  = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius
enum Radius {
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 16
    static let xl: CGFloat  = 20
    static let full: CGFloat = 999
}
