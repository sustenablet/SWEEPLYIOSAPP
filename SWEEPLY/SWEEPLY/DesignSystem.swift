import SwiftUI
import UIKit

// MARK: - Brand Colors
//
// Natural Palette: Clay Terracotta × Warm Stone × Slate
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
    /// Muted Clay/Terracotta — used sparingly for high-intent actions
    static let sweeplyAccent = Color(uiColor: UIColor { trait in
        return trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.65, green: 0.44, blue: 0.35, alpha: 1.0) // Lighter Clay
            : UIColor(red: 0.557, green: 0.349, blue: 0.243, alpha: 1.0) // Deep Clay #8E593E
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

    static let sweeplySuccess     = sweeplyAccent
    static let sweeplyWarning     = Color(red: 0.72, green: 0.55, blue: 0.35)
    static let sweeplyDestructive = Color(red: 0.65, green: 0.25, blue: 0.22)

    /// Muted Stone – adaptive
    static let sweeplyTextSub = Color(uiColor: .secondaryLabel)

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

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
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
