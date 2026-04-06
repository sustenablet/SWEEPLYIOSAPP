import SwiftUI

struct SplashView: View {
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyAccent.opacity(0.1))
                            .frame(width: 96, height: 96)
                        Image(systemName: "sparkles")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                    VStack(spacing: 8) {
                        Text("Sweeply")
                            .font(.system(size: 36, weight: .bold))
                            .tracking(-1.4)
                            .foregroundStyle(Color.sweeplyNavy)
                            .opacity(wordmarkOpacity)

                        Text("Run your cleaning business.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .opacity(taglineOpacity)
                    }
                }

                Spacer()

                ProgressView()
                    .tint(Color.sweeplyAccent)
                    .opacity(taglineOpacity)
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                wordmarkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                taglineOpacity = 1.0
            }
        }
    }
}
