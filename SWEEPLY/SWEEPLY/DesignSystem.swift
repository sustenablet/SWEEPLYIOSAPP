import SwiftUI
import UIKit

// MARK: - Brand Colors
//
 // Refined Palette: Blue-Gray Accent × Warm Stone × Slate
 //
 // ┌─────────────────────────────────────────────────────────────┐
 // │  Color discipline — read before using any sweeply* color    │
 // │                                                             │
 // │  PRIMARY TEXT → Color.primary (system black/white)          │
 // │  SECONDARY TEXT → sweeplyTextSub (muted stone)               │
 // │  NUMBERS & AMOUNTS → Color.primary — never colored          │
 // │  BACKGROUNDS → sweeplyBackground (pages) / sweeplySurface   │
 // └─────────────────────────────────────────────────────────────┘

extension Color {
    /// Blue-Gray Accent — used for high-intent actions and interactive elements
    static let sweeplyAccent = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.41, green: 0.53, blue: 0.63, alpha: 1.0) // Lighter Blue-Gray #6987A0
            : UIColor(red: 0.16, green: 0.33, blue: 0.42, alpha: 1.0) // Deep Blue-Gray #28536B
    })

    /// Slightly more saturated cerulean for the “ly” wordmark (matches brand brush) — a notch more vibrant than `sweeplyAccent` without going neon.
    static let sweeplyWordmarkBlue = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.50, green: 0.65, blue: 0.80, alpha: 1.0)
            : UIColor(red: 0.22, green: 0.52, blue: 0.72, alpha: 1.0)
    })

    /// Slate Charcoal — tab bar, avatar fill, dark UI chrome
    static let sweeplyNavy = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            : UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
    })

    /// Warm Stone — page/scroll background
    static let sweeplyBackground = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
            : UIColor(red: 0.965, green: 0.961, blue: 0.945, alpha: 1.0)
    })

    /// Bone White — card and sheet backgrounds
    static let sweeplySurface = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
            : .white
    })

    /// Vibrant Teal — success state and positive affirmations
    static let sweeplySuccess = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.65, blue: 0.65, alpha: 1.0) // Lighter Teal
            : UIColor(red: 0.15, green: 0.50, blue: 0.50, alpha: 1.0) // Deep Teal #268080
    })

    /// Warm Amber — warning state and attention indicators
    static let sweeplyWarning = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.65, blue: 0.35, alpha: 1.0) // Lighter Amber
            : UIColor(red: 0.75, green: 0.50, blue: 0.25, alpha: 1.0) // Warm Amber #BF8040
    })

    /// Deep Coral — error state and critical alerts
    static let sweeplyDestructive = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.80, green: 0.35, blue: 0.35, alpha: 1.0) // Lighter Coral
            : UIColor(red: 0.70, green: 0.25, blue: 0.25, alpha: 1.0) // Deep Coral #B34040
    })

    /// Muted Stone – adaptive
    static var sweeplyTextSub: Color { Color(uiColor: .secondaryLabel) }

    /// Hairline Slate
    static let sweeplyBorder = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.1)
            : UIColor(red: 0.88, green: 0.87, blue: 0.85, alpha: 1.0)
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

// MARK: - Shared Formatting

extension Double {
    var currency: String {
        Self.currencyFormatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    /// Currency with up to 2 fraction digits; whole amounts omit trailing “.00” (e.g. `$120` vs `$120.00`).
    var currencyWithoutTrailingZeros: String {
        Self.currencyFlexibleFormatter.string(from: NSNumber(value: self)) ?? currency
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private static let currencyFlexibleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

// MARK: - Shared Badges

struct InvoiceStatusBadge: View {
    let status: InvoiceStatus

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .paid:
            return Color.sweeplyAccent
        case .unpaid:
            return Color.sweeplyNavy
        case .overdue:
            return Color.sweeplyDestructive
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .paid:
            return Color.sweeplyAccent.opacity(0.12)
        case .unpaid:
            return Color.sweeplyNavy.opacity(0.10)
        case .overdue:
            return Color.sweeplyDestructive.opacity(0.12)
        }
    }
}

struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .completed:
            return Color.sweeplyAccent
        case .inProgress:
            return .blue
        case .scheduled:
            return Color.sweeplyNavy
        case .cancelled:
            return Color.sweeplyDestructive
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .completed:
            return Color.sweeplyAccent.opacity(0.12)
        case .inProgress:
            return Color.blue.opacity(0.12)
        case .scheduled:
            return Color.sweeplyNavy.opacity(0.10)
        case .cancelled:
            return Color.sweeplyDestructive.opacity(0.12)
        }
    }
}
