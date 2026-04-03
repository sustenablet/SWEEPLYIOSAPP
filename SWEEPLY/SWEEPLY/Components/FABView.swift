import SwiftUI

struct FABView: View {
    @State private var isExpanded = false
    @Binding var selectedTab: RootView.Tab
    var onNewJob: () -> Void
    var onNewClient: () -> Void
    
    let actions: [(label: String, icon: String, tab: RootView.Tab?)] = [
        ("New Invoice", "doc.badge.plus", .finances),
        ("New Client", "person.badge.plus", nil),
        ("New Job", "briefcase.fill", nil),
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
                    ForEach(actions, id: \.label) { action in
                        FABActionButton(label: action.label, icon: action.icon) {
                            withAnimation(.spring(duration: 0.3)) {
                                isExpanded = false
                            }
                            if let tab = action.tab {
                                selectedTab = tab
                            } else if action.label == "New Job" {
                                onNewJob()
                            } else if action.label == "New Client" {
                                onNewClient()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                
                // Main FAB
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy)
                            .frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 80) // above tab bar
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
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.sweeplyNavy)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
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
            onNewClient: {}
        )
    }
}
