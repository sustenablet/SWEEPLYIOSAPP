import SwiftUI

struct CleanerRootView: View {
    @Environment(AppSession.self)          private var session
    @Environment(ProfileStore.self)        private var profileStore
    @Environment(JobsStore.self)           private var jobsStore
    @Environment(NotificationManager.self) private var notificationManager

    let membership: TeamMembership

    @State private var selectedTab: Tab = .dashboard

    enum Tab { case dashboard, upcoming, jobs, finance }

    var body: some View {
        TabView(selection: $selectedTab) {
            CleanerDashboardView(membership: membership)
                .tabItem { Label("Dashboard".translated(), systemImage: "square.grid.2x2.fill") }
                .tag(Tab.dashboard)

            CleanerUpcomingView(membership: membership)
                .tabItem { Label("Schedule".translated(), systemImage: "calendar.badge.clock") }
                .tag(Tab.upcoming)

            CleanerJobsHistoryView(membership: membership)
                .tabItem { Label("Jobs".translated(), systemImage: "list.bullet.rectangle") }
                .tag(Tab.jobs)

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
            async let jobsLoad: () = jobsStore.load(isAuthenticated: session.isAuthenticated)
            if profileStore.profile == nil, let uid = session.userId {
                async let profileLoad: () = profileStore.load(userId: uid)
                _ = await (jobsLoad, profileLoad)
            } else {
                await jobsLoad
            }

            // Schedule recurring local push notification for member's pay day
            notificationManager.scheduleMemberPayDayNotification(membership: membership)

            // Send in-app notification on pay day (once per day, appears in notifications page)
            await sendPayDayInAppNotificationIfNeeded()
        }
    }

    private func sendPayDayInAppNotificationIfNeeded() async {
        guard membership.payRateEnabled && membership.payRateAmount > 0 else { return }
        guard let userId = session.userId else { return }

        let isPayDay: Bool
        switch membership.payRateType {
        case .perDay: isPayDay = true
        case .perWeek:
            let weekday = Calendar.current.component(.weekday, from: Date())
            isPayDay = membership.payDayOfWeek == weekday
        default: isPayDay = false
        }
        guard isPayDay else { return }

        // Guard against sending multiple times the same day using UserDefaults
        let dateKey = DateFormatter()
        dateKey.dateFormat = "yyyy-MM-dd"
        let todayStr = dateKey.string(from: Date())
        let storageKey = "payDayNotifSent_\(membership.id.uuidString)_\(todayStr)"
        guard !UserDefaults.standard.bool(forKey: storageKey) else { return }

        await NotificationHelper.insert(
            userId: userId,
            title: "It's Pay Day!",
            message: "Your \(membership.payRateAmount.currency) from \(membership.businessName) should be processed today. Check with your manager.",
            kind: "billing"
        )
        UserDefaults.standard.set(true, forKey: storageKey)
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
