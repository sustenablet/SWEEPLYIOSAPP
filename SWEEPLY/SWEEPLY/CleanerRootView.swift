import SwiftUI

struct CleanerRootView: View {
    @Environment(AppSession.self)   private var session
    @Environment(ProfileStore.self) private var profileStore

    let membership: TeamMembership

    @State private var selectedTab: Tab = .dashboard

    enum Tab { case dashboard, upcoming, finance }

    var body: some View {
        TabView(selection: $selectedTab) {
            CleanerDashboardView(membership: membership)
                .tabItem { Label("Dashboard".translated(), systemImage: "square.grid.2x2.fill") }
                .tag(Tab.dashboard)

            CleanerUpcomingView(membership: membership)
                .tabItem { Label("Schedule".translated(), systemImage: "calendar.badge.clock") }
                .tag(Tab.upcoming)

            CleanerFinanceView(membership: membership)
                .tabItem { Label("Finance".translated(), systemImage: "dollarsign.circle.fill") }
                .tag(Tab.finance)
        }
        .tint(Color.sweeplyAccent)
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onAppear { applyTabBarAppearance() }
        .task {
            // Ensure profile is loaded when entering member view (handles app-restore race condition)
            if profileStore.profile == nil, let uid = session.userId {
                await profileStore.load(userId: uid)
            }
        }
    }

    private func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.sweeplyNavy)

        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 1, alpha: 0.35)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(white: 1, alpha: 0.35),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        let accentUIColor = UIColor(Color.sweeplyAccent)
        appearance.stackedLayoutAppearance.selected.iconColor = accentUIColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: accentUIColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
