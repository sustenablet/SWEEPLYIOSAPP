import SwiftUI

struct CleanerRootView: View {
    @Environment(AppSession.self)   private var session
    @Environment(ProfileStore.self) private var profileStore
    @Environment(JobsStore.self)    private var jobsStore

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
            // Load jobs and profile immediately when entering member view.
            // This ensures member data is ready on app restart, not relying solely
            // on RootView's onChange(of: currentViewMode) which fires asynchronously.
            async let jobsLoad: () = jobsStore.load(isAuthenticated: session.isAuthenticated)
            if profileStore.profile == nil, let uid = session.userId {
                async let profileLoad: () = profileStore.load(userId: uid)
                _ = await (jobsLoad, profileLoad)
            } else {
                await jobsLoad
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
