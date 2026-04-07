import SwiftUI

// MARK: - Shimmer Modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { _ in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.45), location: 0.45),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: UnitPoint(x: phase, y: 0),
                        endPoint: UnitPoint(x: phase + 0.6, y: 0)
                    )
                    .blendMode(.screen)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Block

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 13
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.sweeplyBorder.opacity(0.8))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Skeleton Row (list/card row placeholder)

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.sweeplyBorder.opacity(0.8))
                .frame(width: 46, height: 46)
                .shimmer()

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 140, height: 13)
                SkeletonBlock(width: 100, height: 10)
            }

            Spacer()

            SkeletonBlock(width: 48, height: 13)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

// MARK: - Skeleton Card (full card with multiple lines)

struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonBlock(width: 160, height: 15)
                Spacer()
                SkeletonBlock(width: 58, height: 13)
            }
            SkeletonBlock(width: 120, height: 11)
            SkeletonBlock(width: 90, height: 10)
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

// MARK: - Skeleton List

struct SkeletonList: View {
    var count: Int = 4

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .padding(.horizontal, 20)
    }
}
