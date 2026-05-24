import SwiftUI

struct FABView: View {
    @State private var isExpanded = false
    @Binding var selectedTab: RootView.Tab
    var onNewJob: () -> Void
    var onNewClient: () -> Void
    var onNewInvoice: () -> Void

    private let actions: [(label: String, icon: String, tag: String)] = [
        ("New Invoice", "doc.badge.plus", "invoice"),
        ("New Client", "person.badge.plus", "client"),
        ("New Job", "briefcase.fill", "job"),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .onTapGesture {
                        collapseActions()
                    }
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: 12) {
                if isExpanded {
                    ForEach(actions, id: \.tag) { action in
                        FABActionButton(
                            label: action.label,
                            icon: action.icon
                        ) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            collapseActions()
                            switch action.tag {
                            case "job": onNewJob()
                            case "client": onNewClient()
                            case "invoice": onNewInvoice()
                            default: break
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .offset(y: 16).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .trailing)),
                            removal: .offset(y: 10).combined(with: .opacity)
                        ))
                    }
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toggleActions()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy)
                            .frame(width: 58, height: 58)
                            .shadow(color: Color.sweeplyNavy.opacity(0.4), radius: 14, x: 0, y: 5)

                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                            .scaleEffect(isExpanded ? 0.94 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isExpanded)
    }

    private func toggleActions() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            isExpanded.toggle()
        }
    }

    private func collapseActions() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isExpanded = false
        }
    }
}

struct FABActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Color.sweeplyNavy)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
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
            onNewInvoice: {}
        )
    }
}
