import SwiftUI

struct FABView: View {
    @State private var isExpanded = false
    @Binding var selectedTab: RootView.Tab
    var onNewJob: () -> Void
    var onNewClient: () -> Void
    var onNewInvoice: () -> Void
    var onAIChat: () -> Void

    private let actions: [(label: String, icon: String, tag: String)] = [
        ("AI Assistant", "sparkles", "ai"),
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
                            // Brand "S" mark
                            VStack(spacing: -2) {
                                Text("S")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
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
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isAI ? Color.sweeplyNavy : .white)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isAI ? Color.sweeplyNavy : .white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isAI ? Color.sweeplyAccent.opacity(0.15) : Color.sweeplyNavy)
            .clipShape(Capsule())
            .overlay(
                isAI ? Capsule().stroke(Color.sweeplyAccent.opacity(0.4), lineWidth: 1.5) : nil
            )
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
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
