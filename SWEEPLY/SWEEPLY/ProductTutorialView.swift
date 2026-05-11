import SwiftUI

struct ProductTutorialView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var goingForward = true
    private let totalPages = 4

    var body: some View {
        ZStack {
            Color.sweeplyNavy.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                segmentedProgress
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text(pages[page].eyebrow)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyAccent)
                        .tracking(0.6)

                    Text(pages[page].headline)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                ZStack {
                    TutorialPhoneFrame {
                        pages[page].preview
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal:   .move(edge: goingForward ? .leading  : .trailing).combined(with: .opacity)
                        )
                    )
                    .id(page)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    advance()
                } label: {
                    Text(page == totalPages - 1 ? "Get started".translated() : "Continue".translated())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.sweeplyAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.width < -50 {
                    advance()
                } else if value.translation.width > 50 && page > 0 {
                    goingForward = false
                    withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if page > 0 {
                Button {
                    goingForward = false
                    withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                }
            } else {
                Spacer().frame(width: 44, height: 44)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onComplete()
            } label: {
                Text("Skip".translated())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Segmented Progress

    private var segmentedProgress: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalPages, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= page ? Color.white : Color.white.opacity(0.18))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
    }

    // MARK: - Advance

    private func advance() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if page < totalPages - 1 {
            goingForward = true
            withAnimation(.easeInOut(duration: 0.28)) { page += 1 }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete()
        }
    }

    // MARK: - Pages

    private var pages: [TutorialPage] {
        [
            TutorialPage(
                eyebrow: "SCHEDULING".translated(),
                headline: "Book a job in\n20 seconds.".translated(),
                preview: AnyView(ScheduleTutorialPreview())
            ),
            TutorialPage(
                eyebrow: "INVOICING".translated(),
                headline: "Send invoices.\nGet paid.".translated(),
                preview: AnyView(FinancesTutorialPreview())
            ),
            TutorialPage(
                eyebrow: "YOU'RE READY".translated(),
                headline: "Let's go.".translated(),
                preview: AnyView(ReadyTutorialPreview())
            )
        ]
    }
}

// MARK: - Page Model

private struct TutorialPage {
    let eyebrow: String
    let headline: String
    let preview: AnyView
}

// MARK: - Phone Frame

private struct TutorialPhoneFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 80, height: 26)
                    .padding(.top, 10)

                content()
                    .padding(10)
                    .padding(.bottom, 12)
            }
        }
        .aspectRatio(9 / 19.5, contentMode: .fit)
        .shadow(color: Color.sweeplyAccent.opacity(0.12), radius: 40, y: 20)
    }
}

// MARK: - Page Previews

private struct ScheduleTutorialPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today".translated())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)

            HStack(spacing: 3) {
                let days = [("M", 21), ("T", 22), ("W", 23), ("T", 24), ("F", 25)]
                ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                    VStack(spacing: 3) {
                        Text(day.0)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("\(day.1)")
                            .font(.system(size: 10, weight: idx == 1 ? .bold : .regular))
                            .foregroundStyle(idx == 1 ? .white : Color.primary)
                            .frame(width: 20, height: 20)
                            .background(idx == 1 ? Color.sweeplyAccent : Color.clear)
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 6) {
                timelineRow(time: "9:00", color: Color.sweeplyAccent, client: "Sarah M.", service: "Standard Clean")
                Divider().padding(.leading, 54)
                timelineRow(time: "11:30", color: Color.sweeplyWarning, client: "John D.", service: "Deep Clean")
                Divider().padding(.leading, 54)
                timelineRow(time: "2:00", color: Color.sweeplyAccent, client: "Lisa K.", service: "Move In/Out")
            }
            .padding(10)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func timelineRow(time: String, color: Color, client: String, service: String) -> some View {
        HStack(spacing: 8) {
            Text(time)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 30, alignment: .trailing)
            Circle().fill(color).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(client).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.sweeplyNavy)
                Text(service).font(.system(size: 8)).foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
        }
    }
}

private struct FinancesTutorialPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS MONTH".translated())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.5)
                Text("$3,200".translated())
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack(spacing: 4) {
                ForEach([0.4, 0.6, 0.5, 0.75, 0.55, 0.9], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.sweeplyAccent.opacity(0.3 + h * 0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(h) * 30)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            VStack(spacing: 5) {
                invoiceRow(number: "INV-0024", client: "Sarah M.", amount: "$320", status: "PAID", statusColor: .green)
                Divider().padding(.horizontal, 10)
                invoiceRow(number: "INV-0025", client: "John D.", amount: "$180", status: "OVERDUE", statusColor: Color.sweeplyDestructive)
            }
            .padding(8)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func invoiceRow(number: String, client: String, amount: String, status: String, statusColor: Color) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(number).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(Color.sweeplyNavy)
                Text(client).font(.system(size: 7)).foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Text(status)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(statusColor.opacity(0.1)).clipShape(Capsule())
            Text(amount).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 4)
    }
}

private struct ReadyTutorialPreview: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 60, height: 60)
                Text("S")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 5) {
                Text("Sweeply")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Run jobs. Get paid. Grow.".translated())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            VStack(spacing: 6) {
                readyRow(icon: "calendar.badge.checkmark", label: "Scheduling".translated())
                readyRow(icon: "doc.text.fill", label: "Invoicing".translated())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func readyRow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.sweeplyAccent)
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.sweeplyNavy)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.sweeplySurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

#Preview {
    ProductTutorialView(onComplete: {})
}
