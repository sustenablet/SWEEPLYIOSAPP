import SwiftUI

struct GetStartedView: View {
    let onSignUp: () -> Void
    let onLogIn: () -> Void

    @State private var appeared = false
    @State private var displayedText = ""
    private var fullText: String { "Welcome to Sweeply".translated() }

    @State private var charIndex = 0

    var body: some View {
        ZStack {
            Image("GetStartedBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                textSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                Spacer().frame(height: 36)

                buttonRow
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.05)) { appeared = true }
            startTypewriter()
        }
    }

    private func startTypewriter() {
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            if charIndex <= fullText.count {
                let index = fullText.index(fullText.startIndex, offsetBy: charIndex)
                displayedText = String(fullText[..<index])
                charIndex += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                timer.invalidate()
            }
        }
    }

    private var textSection: some View {
        VStack(spacing: 10) {
            Text(displayedText)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .tracking(-0.6)
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

    private var buttonRow: some View {
        HStack(spacing: 12) {
            // Log In — outlined
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onLogIn()
            } label: {
                Text("Log In".translated())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.45), lineWidth: 1.5)
                    )
            }

            // Sign Up — solid blue
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSignUp()
            } label: {
                Text("Sign Up".translated())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.sweeplyWordmarkBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.sweeplyWordmarkBlue.opacity(0.4), radius: 10, y: 4)
            }
        }
    }
}

#Preview {
    GetStartedView(onSignUp: {}, onLogIn: {})
}
