import SwiftUI

struct GetStartedView: View {
    let onGetStarted: () -> Void

    @State private var appeared = false
    @State private var displayedText = ""
    private var fullText: String { "Welcome to Sweeply".translated() }
    private var typedText: AttributedString {
        var result = AttributedString()
        let welcome = AttributedString("Welcome to ")
        var sweeply = AttributedString("Sweeply")
        sweeply.foregroundColor = Color.sweeplyWordmarkBlue
        result.append(welcome)
        result.append(sweeply)
        return result
    }
    @State private var charIndex = 0

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
                    .frame(height: 28)

                getStartedButton
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.05)) {
                appeared = true
            }
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
                .background(Color.sweeplyWordmarkBlue)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

#Preview {
    GetStartedView {
        print("Get started tapped")
    }
}
