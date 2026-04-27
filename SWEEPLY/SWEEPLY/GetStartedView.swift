import SwiftUI

struct GetStartedView: View {
    let onGetStarted: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Full-bleed background image
            Image("GetStartedBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Dark gradient overlay for legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                textSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                Spacer()
                    .frame(height: 32)

                getStartedButton
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.1)) {
                appeared = true
            }
        }
    }

    private var textSection: some View {
        VStack(spacing: 10) {
            Text("Welcome to Sweeply".translated())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .tracking(-0.5)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            Text("Run your cleaning business with ease. Track jobs, manage clients, and grow your business.".translated())
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
    }

    private var getStartedButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onGetStarted()
        } label: {
            Text("Get Started".translated())
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.sweeplyAccent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

#Preview {
    GetStartedView {
        print("Get started tapped")
    }
}
