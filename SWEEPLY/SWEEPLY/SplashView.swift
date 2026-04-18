import SwiftUI

struct SplashView: View {
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 32)
                    .opacity(contentOpacity)

                Spacer()
                    .frame(height: 120)

                ProgressView()
                    .tint(Color.sweeplyAccent)
                    .opacity(contentOpacity)
                    .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                contentOpacity = 1.0
            }
        }
    }
}
