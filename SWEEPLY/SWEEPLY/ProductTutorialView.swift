import SwiftUI

/// First-launch product walkthrough (Notion-style): dark chrome, segmented progress, phone mockups.
struct ProductTutorialView: View {
    var onComplete: () -> Void

    @State private var page = 0
    private let totalPages = 5

    private let bg = Color(red: 0.07, green: 0.07, blue: 0.09)
    private let subtle = Color.white.opacity(0.45)
    private let ctaBlue = Color(red: 0.18, green: 0.47, blue: 0.98)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                segmentedProgress
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Some essential tips")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(subtle)

                    Text(pages[page].headline)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                TutorialPhoneFrame {
                    pages[page].preview
                }
                .padding(.horizontal, 28)

                Spacer()

                Button {
                    advance()
                } label: {
                    Text(page == totalPages - 1 ? "Finish" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(ctaBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if page > 0 {
                    withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(page > 0 ? Color.white : Color.clear)
                    .frame(width: 44, height: 44)
            }
            .disabled(page == 0)

            Spacer()
        }
    }

    private var segmentedProgress: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalPages, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= page ? Color.white : Color.white.opacity(0.18))
                    .frame(height: 3)
            }
        }
    }

    private func advance() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if page < totalPages - 1 {
            withAnimation(.easeInOut(duration: 0.28)) { page += 1 }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete()
        }
    }

    private var pages: [TutorialPage] {
        [
            TutorialPage(
                headline: "Your cleaning business, organized in one place.",
                preview: AnyView(DashboardTutorialPreview())
            ),
            TutorialPage(
                headline: "See every visit on the schedule — by day or list.",
                preview: AnyView(ScheduleTutorialPreview())
            ),
            TutorialPage(
                headline: "Keep every client and job site in one directory.",
                preview: AnyView(ClientsTutorialPreview())
            ),
            TutorialPage(
                headline: "Track invoices and cash flow without spreadsheets.",
                preview: AnyView(FinancesTutorialPreview())
            ),
            TutorialPage(
                headline: "You’re ready. Run jobs, get paid, and grow.",
                preview: AnyView(ReadyTutorialPreview())
            )
        ]
    }
}

private struct TutorialPage {
    let headline: String
    let preview: AnyView
}

// MARK: - Phone frame

private struct TutorialPhoneFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 88, height: 28)
                    .padding(.top, 10)

                content()
                    .padding(10)
                    .padding(.bottom, 12)
            }
        }
        .aspectRatio(9 / 19.5, contentMode: .fit)
        .shadow(color: .white.opacity(0.08), radius: 40, y: 20)
    }
}

// MARK: - Preview contents (light “app inside phone”)

private struct DashboardTutorialPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.sweeplyBackground)
                .frame(height: 44)
                .overlay(alignment: .leading) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.sweeplyAccent.opacity(0.3)).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.sweeplyNavy.opacity(0.2)).frame(width: 80, height: 6)
                            RoundedRectangle(cornerRadius: 2).fill(Color.sweeplyTextSub.opacity(0.25)).frame(width: 50, height: 4)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.sweeplySurface)
                        .frame(height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ScheduleTutorialPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("April")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
            }
            HStack(spacing: 4) {
                let letters = ["S", "M", "T", "W", "T", "F", "S"]
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(letters[i])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("\(29 + i)")
                            .font(.system(size: 11, weight: i == 2 ? .bold : .regular))
                            .foregroundStyle(i == 2 ? Color.white : Color.primary)
                            .frame(width: 22, height: 22)
                            .background(i == 2 ? Color.sweeplySuccess : Color.clear)
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.sweeplySurface)
                .frame(height: 56)
                .overlay(alignment: .leading) {
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(Color.sweeplySuccess).frame(width: 3, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("9:00 AM")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Standard clean")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ClientsTutorialPreview: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.sweeplyNavy)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(["A", "B", "C", "D"][i])
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.sweeplyNavy.opacity(0.2)).frame(width: 100 - CGFloat(i * 10), height: 7)
                        RoundedRectangle(cornerRadius: 2).fill(Color.sweeplyTextSub.opacity(0.2)).frame(width: 70, height: 5)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FinancesTutorialPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.sweeplyNavy.opacity(0.15 + Double(h) * 0.08))
                        .frame(width: 14, height: 24 + CGFloat(h * 8))
                }
            }
            .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.sweeplySurface)
                .frame(height: 40)
                .overlay(
                    HStack {
                        Text("INV-0042")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("$320")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ReadyTutorialPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.sweeplySuccess)
                .shadow(color: Color.sweeplySuccess.opacity(0.4), radius: 16)
            Text("Sweeply")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
            Text("Clients · Jobs · Invoices")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ProductTutorialView(onComplete: {})
}
