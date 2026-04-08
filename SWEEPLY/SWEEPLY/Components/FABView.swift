import SwiftUI

struct FABView: View {
    @State private var isExpanded = false
    @Binding var selectedTab: RootView.Tab
    var onNewJob: () -> Void
    var onNewClient: () -> Void
    var onNewInvoice: () -> Void
    var onAIChat: () -> Void

    private let actions: [(label: String, icon: String, tag: String)] = [
        ("Ask AI", "sparkles", "ai"),
        ("New Invoice", "doc.badge.plus", "invoice"),
        ("New Client", "person.badge.plus", "client"),
        ("New Job", "briefcase.fill", "job"),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrim when expanded
            if isExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) {
                            isExpanded = false
                        }
                    }
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: 12) {
                // Expanded action buttons
                if isExpanded {
                    ForEach(actions, id: \.tag) { action in
                        FABActionButton(
                            label: action.label,
                            icon: action.icon,
                            isAI: action.tag == "ai"
                        ) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(duration: 0.3)) {
                                isExpanded = false
                            }
                            switch action.tag {
                            case "ai": onAIChat()
                            case "job": onNewJob()
                            case "client": onNewClient()
                            case "invoice": onNewInvoice()
                            default: break
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }

                // Main FAB — Sweeply brand button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy)
                            .frame(width: 58, height: 58)
                            .shadow(color: Color.sweeplyNavy.opacity(0.4), radius: 14, x: 0, y: 5)

                        if isExpanded {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            // Brand "S" mark with AI sparkle hint
                            ZStack {
                                Text("S")
                                    .font(.system(size: 22, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .offset(x: 13, y: -13)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 80)
        }
    }
}

struct FABActionButton: View {
    let label: String
    let icon: String
    var isAI: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isAI {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyAccent.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isAI ? Color.sweeplyNavy : .white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                isAI
                    ? LinearGradient(colors: [Color.sweeplyAccent.opacity(0.18), Color.sweeplyAccent.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.sweeplyNavy, Color.sweeplyNavy], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
            .overlay(
                isAI ? Capsule().stroke(Color.sweeplyAccent.opacity(0.5), lineWidth: 1.5) : nil
            )
            .shadow(color: isAI ? Color.sweeplyAccent.opacity(0.15) : Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.sweeplyBackground.ignoresSafeArea()
        FABView(
            selectedTab: .constant(.dashboard),
            onNewJob: {},
            onNewClient: {},
            onNewInvoice: {},
            onAIChat: {}
        )
    }
}
