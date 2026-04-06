import SwiftUI

struct RootView: View {
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self)  private var profileStore

    @State private var selectedTab: Tab = .dashboard
    @State private var showNewJob = false
    @State private var showNewClient = false
    @State private var showNewInvoice = false
    @State private var showQuickAdd = false
    @State private var showOnboarding = false

    enum Tab {
        case dashboard, schedule, clients, finances, business
    }

    var body: some View {
        Group {
            if !SupabaseManager.isConfigured {
                mainTabs
            } else if !session.hasResolvedInitialSession {
                ZStack {
                    Color.sweeplyBackground.ignoresSafeArea()
                    ProgressView()
                        .tint(Color.sweeplyAccent)
                }
            } else if session.isAuthenticated {
                mainTabs
            } else {
                AuthView()
            }
        }
        .preferredColorScheme(profileStore.profile?.settings.darkMode == true ? .dark : nil)
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

            FABView(
                selectedTab: $selectedTab, 
                onNewJob: { showNewJob = true },
                onNewClient: { showNewClient = true },
                onNewInvoice: { showNewInvoice = true }
            )
        }
        .sheet(isPresented: $showNewJob) {
            NewJobForm()
        }
        .sheet(isPresented: $showNewClient) {
            NewClientForm()
        }
        .sheet(isPresented: $showNewInvoice) {
            NewInvoiceView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onChange(of: profileStore.profile) { _, profile in
            guard session.isAuthenticated, let profile else { return }
            if profile.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showOnboarding = true
            } else {
                showOnboarding = false
            }
        }

        .task(id: session.isAuthenticated) {
            async let j: () = jobsStore.load(isAuthenticated: session.isAuthenticated)
            async let i: () = invoicesStore.load(isAuthenticated: session.isAuthenticated)
            _ = await (j, i)
            await invoicesStore.markOverdueInvoices()
            if session.isAuthenticated, let uid = session.userId {
                await profileStore.load(userId: uid)
            }
            await clientsStore.load(isAuthenticated: session.isAuthenticated)
        }
        .onChange(of: session.isAuthenticated) { _, authed in
            if !authed {
                clientsStore.clear()
                jobsStore.clear()
                invoicesStore.clear()
                profileStore.clear()
            }
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
