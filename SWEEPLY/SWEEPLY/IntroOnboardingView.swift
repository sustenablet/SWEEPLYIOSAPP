import SwiftUI

struct IntroOnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let pages: [IntroPage] = [
        IntroPage(
            title: "Your Cleaning Business.\nIn Control.",
            subtitle: "Jobs, clients, and payments - organized in one place.".translated(),
            imageName: "IntroOnboardingHero"
        ),
        IntroPage(
            title: "Schedule Smarter",
            subtitle: "Create jobs, assign cleaners, and track status in real time.".translated(),
            imageName: nil,
            iconName: "calendar.badge.clock"
        ),
        IntroPage(
            title: "Get Paid Faster",
            subtitle: "Send invoices and track paid, unpaid, and overdue balances.".translated(),
            imageName: nil,
            iconName: "dollarsign.circle"
        )
    ]

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, entry in
                        IntroPageView(page: entry)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { idx in
                        Capsule()
                            .fill(idx == page ? Color.sweeplyAccent : Color.sweeplyBorder)
                            .frame(width: idx == page ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: page)
                    }
                }
                .padding(.top, 12)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if page < pages.count - 1 {
                        withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Get Started" : "Next")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.sweeplyAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 42)
            }
        }
    }
}

private struct IntroPageView: View {
    let page: IntroPage

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if let imageName = page.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                } else if let iconName = page.iconName {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.sweeplyAccent.opacity(0.1))
                            .frame(width: 132, height: 132)
                        Image(systemName: iconName)
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .padding(.top, 52)
                }

                Text(page.title)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text(page.subtitle)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
    }
}

private struct IntroPage {
    let title: String
    let subtitle: String
    let imageName: String?
    let iconName: String?

    init(title: String, subtitle: String, imageName: String? = nil, iconName: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.imageName = imageName
        self.iconName = iconName
    }
}

#Preview {
    IntroOnboardingView(onFinish: {})
}
