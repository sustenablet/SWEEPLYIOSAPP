import SwiftUI

struct SplashView: View {
    @State private var contentOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(contentOpacity)

                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                contentOpacity = 1.0
            }
        }
    }
}
