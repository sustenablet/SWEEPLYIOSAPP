import SwiftUI

struct CleanerRootView: View {
    @Environment(AppSession.self) private var session

    let membership: TeamMembership

    @State private var selectedTab: Tab = .dashboard

    enum Tab { case dashboard, upcoming, profile }

    var body: some View {
        TabView(selection: $selectedTab) {
            CleanerDashboardView(membership: membership)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.dashboard)

            CleanerUpcomingView(membership: membership)
                .tabItem { Label("Upcoming", systemImage: "calendar") }
                .tag(Tab.upcoming)

            CleanerProfileView(membership: membership)
                .tabItem { Label("Profile", systemImage: "person.circle.fill") }
                .tag(Tab.profile)
        }
        .tint(Color.sweeplyAccent)
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onAppear { applyTabBarAppearance() }
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
