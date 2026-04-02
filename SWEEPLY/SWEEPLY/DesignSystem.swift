import SwiftUI

// MARK: - Brand Colors
extension Color {
    static let sweeplyAccent      = Color(red: 0.976, green: 0.635, blue: 0.063) // amber #F9A110
    static let sweeplyNavy        = Color(red: 0.070, green: 0.090, blue: 0.140) // deep navy
    static let sweeplyBackground  = Color(red: 0.945, green: 0.948, blue: 0.958) // cool off-white
    static let sweeplySuccess     = Color(red: 0.086, green: 0.639, blue: 0.290) // green
    static let sweeplyWarning     = Color(red: 0.976, green: 0.635, blue: 0.063) // amber (same as accent)
    static let sweeplyDestructive = Color(red: 0.859, green: 0.157, blue: 0.141) // red
    static let sweeplyTextSub     = Color(red: 0.450, green: 0.478, blue: 0.545) // muted text
    static let sweeplySurface     = Color.white
    static let sweeplyBorder      = Color(red: 0.880, green: 0.882, blue: 0.900)
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
