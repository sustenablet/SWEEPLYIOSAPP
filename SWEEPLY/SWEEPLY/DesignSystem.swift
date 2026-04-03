import SwiftUI
import UIKit

// MARK: - Brand Colors
//
// Palette: Warm Linen × Forest Green (Light) / Deep Slate × Forest Green (Dark)
//
// ┌─────────────────────────────────────────────────────────────┐
// │  Color discipline — read before using any sweeply* color    │
// │                                                             │
// │  PRIMARY TEXT → Color.primary (system black/white)          │
// │  SECONDARY TEXT → sweeplyTextSub (gray)                     │
// │  NUMBERS & AMOUNTS → Color.primary — never colored          │
// │  BACKGROUNDS → sweeplyBackground (pages) / sweeplySurface   │
// └─────────────────────────────────────────────────────────────┘

extension Color {
    /// Forest green — CTA buttons, selected state, checkmarks, "Paid" badge
    static let sweeplyAccent = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.141, green: 0.700, blue: 0.480, alpha: 1.0) // Vibrancy boost for dark
            : UIColor(red: 0.106, green: 0.600, blue: 0.400, alpha: 1.0)
    })

    /// Near-black (Light) / Elevated Gray (Dark)
    static let sweeplyNavy = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0) // Elevated gray for contrast
            : UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1.0)
    })

    /// Warm linen (Light) / Near-black (Dark)
    static let sweeplyBackground = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
            : UIColor(red: 0.965, green: 0.961, blue: 0.945, alpha: 1.0)
    })

    /// White (Light) / Deep Gray (Dark)
    static let sweeplySurface = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            : .white
    })

    static let sweeplySuccess     = sweeplyAccent
    static let sweeplyWarning     = Color(red: 0.812, green: 0.545, blue: 0.055)
    static let sweeplyDestructive = Color(red: 0.780, green: 0.200, blue: 0.200)

    /// Mid-gray – adaptive
    static let sweeplyTextSub = Color(uiColor: .secondaryLabel)

    /// Dynamic border color
    static let sweeplyBorder = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.1)
            : UIColor(red: 0.902, green: 0.898, blue: 0.886, alpha: 1.0)
    })
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
