import SwiftUI

struct RootView: View {
    @State private var selectedTab: Tab = .dashboard

    enum Tab {
        case dashboard, schedule, clients, invoices, finances
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.dashboard)

            PlaceholderView(title: "Schedule", icon: "calendar")
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Tab.schedule)

            ClientsView()
                .tabItem { Label("Clients", systemImage: "person.2.fill") }
                .tag(Tab.clients)

            PlaceholderView(title: "Invoices", icon: "doc.text.fill")
                .tabItem { Label("Invoices", systemImage: "doc.text.fill") }
                .tag(Tab.invoices)

            PlaceholderView(title: "Finances", icon: "chart.line.uptrend.xyaxis")
                .tabItem { Label("Finances", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.finances)
        }
        .tint(Color.sweeplyAccent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.sweeplyNavy)

            // Normal item color
            appearance.stackedLayoutAppearance.normal.iconColor   = UIColor(white: 1, alpha: 0.35)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(white: 1, alpha: 0.35),
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]

            // Selected item color
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
}

// MARK: - Placeholder for unbuilt screens
struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()
            VStack(spacing: Spacing.base) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                Text("Coming soon")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
            }
        }
    }
}

#Preview {
    RootView()
}
