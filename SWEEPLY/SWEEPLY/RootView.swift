import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(ClientsStore.self) private var clientsStore

    @State private var selectedTab: Tab = .dashboard
    @State private var showQuickAdd = false

    enum Tab {
        case dashboard, schedule, clients, finances, business
    }

    var body: some View {
        // Auth is bypassed during UI development — go straight to the main app.
        mainTabs
    }

    private var mainTabs: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                    .tag(Tab.dashboard)

                ScheduleView()
                    .tabItem { Label("Schedule", systemImage: "calendar") }
                    .tag(Tab.schedule)

                ClientsView()
                    .tabItem { Label("Clients", systemImage: "person.2.fill") }
                    .tag(Tab.clients)

                FinancesView()
                    .tabItem { Label("Finances", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(Tab.finances)

                BusinessView()
                    .tabItem { Label("Business", systemImage: "building.2.fill") }
                    .tag(Tab.business)
            }
            .tint(Color.sweeplyAccent)

            if selectedTab == .dashboard {
                Button {
                    showQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.sweeplyNavy)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 72)
                .accessibilityLabel("Quick actions")
            }
        }
        .confirmationDialog("Quick actions", isPresented: $showQuickAdd, titleVisibility: .visible) {
            Button("New invoice") {
                selectedTab = .finances
            }
            Button("New job") {
                selectedTab = .schedule
            }
            Button("New client") {
                selectedTab = .clients
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create something new")
        }
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.sweeplyNavy)

            appearance.stackedLayoutAppearance.normal.iconColor   = UIColor(white: 1, alpha: 0.35)
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
}

#Preview {
    RootView()
        .environment(AppSession())
        .environment(ClientsStore())
}
