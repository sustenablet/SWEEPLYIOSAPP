import SwiftUI

struct PageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    private let headerHeight: CGFloat = 76

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(1.3)
                }

                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .frame(minHeight: headerHeight, alignment: .center)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct HeaderIconButton: View {
    let systemName: String
    var foregroundColor: Color = Color.sweeplyNavy
    var backgroundColor: Color = Color.sweeplySurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 40, height: 40)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
