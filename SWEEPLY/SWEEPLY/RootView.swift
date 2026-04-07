import SwiftUI
import LocalAuthentication

struct RootView: View {
    @Environment(AppSession.self)          private var session
    @Environment(ClientsStore.self)        private var clientsStore
    @Environment(JobsStore.self)           private var jobsStore
    @Environment(InvoicesStore.self)       private var invoicesStore
    @Environment(ProfileStore.self)        private var profileStore
    @Environment(NotificationManager.self) private var notificationManager

    @State private var selectedTab: Tab = .dashboard
    @State private var deepLinkedJobId: UUID? = nil
    @State private var deepLinkedInvoiceId: UUID? = nil
    @State private var showNewJob = false
    @State private var showNewClient = false
    @State private var showNewInvoice = false
    @State private var showQuickAdd = false
    @State private var showAIChat = false
    @State private var showOnboarding = false
    @State private var isLocked = false

    @AppStorage("biometricLockEnabled") private var biometricLockEnabled: Bool = false
    @AppStorage("pendingShortcut") private var pendingShortcut: String = ""
    @AppStorage("pendingSpotlightLink") private var pendingSpotlightLink: String = ""

    enum Tab {
        case dashboard, schedule, clients, finances, business
    }

    private var overdueInvoiceCount: Int {
        invoicesStore.invoices.filter { $0.status == .overdue }.count
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !SupabaseManager.isConfigured {
                mainTabs
            } else if !session.hasResolvedInitialSession {
                SplashView()
            } else if session.isAuthenticated {
                ZStack {
                    mainTabs
                    if isLocked {
                        biometricLockOverlay
                    }
                }
            } else {
                AuthView()
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && biometricLockEnabled {
                isLocked = true
            } else if phase == .active && isLocked {
                authenticate()
            } else if phase == .active && !pendingShortcut.isEmpty {
                handlePendingShortcut()
            } else if phase == .active && !pendingSpotlightLink.isEmpty {
                handleSpotlightLink()
            }
        }
    }

    private func handleSpotlightLink() {
        let link = pendingSpotlightLink
        pendingSpotlightLink = ""
        if link.hasPrefix("client:") {
            selectedTab = .clients
        } else if link.hasPrefix("job:") {
            selectedTab = .schedule
        }
    }

    private func handlePendingShortcut() {
        let shortcut = pendingShortcut
        pendingShortcut = ""
        switch shortcut {
        case "com.sweeply.newjob":
            showNewJob = true
        case "com.sweeply.ai":
            showAIChat = true
        case "com.sweeply.schedule":
            selectedTab = .schedule
        default:
            break
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Sweeply") { success, _ in
                DispatchQueue.main.async {
                    if success { isLocked = false }
                }
            }
        } else {
            // Fall back to passcode
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Sweeply") { success, _ in
                DispatchQueue.main.async {
                    if success { isLocked = false }
                }
            }
        }
    }

    private var biometricLockOverlay: some View {
        ZStack {
            Color.sweeplyNavy.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 100, height: 100)
                    Text("S")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 10) {
                    Text("Sweeply is Locked")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Your business data is protected.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    authenticate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Unlock Sweeply")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.sweeplyNavy)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.white)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 48)
            }
        }
        .transition(.opacity)
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
                    .badge(overdueInvoiceCount > 0 ? overdueInvoiceCount : 0)

                BusinessView()
                    .tabItem { Label("Business", systemImage: "building.2.fill") }
                    .tag(Tab.business)
            }
            .tint(Color.sweeplyAccent)

            FABView(
                selectedTab: $selectedTab,
                onNewJob: { showNewJob = true },
                onNewClient: { showNewClient = true },
                onNewInvoice: { showNewInvoice = true },
                onAIChat: { showAIChat = true }
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
        .sheet(isPresented: $showAIChat) {
            AIChatView(
                onNewJob: { showNewJob = true },
                onNewClient: { showNewClient = true },
                onNewInvoice: { showNewInvoice = true }
            )
            .environment(jobsStore)
            .environment(clientsStore)
            .environment(invoicesStore)
            .environment(profileStore)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onChange(of: profileStore.profile?.businessName ?? "") { _, businessName in
            guard session.isAuthenticated else { return }
            if businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        .onChange(of: notificationManager.pendingDeepLink) { _, link in
            guard let link else { return }
            switch link {
            case .job(let id):
                selectedTab = .schedule
                deepLinkedJobId = id
            case .invoice(let id):
                selectedTab = .finances
                deepLinkedInvoiceId = id
            }
            notificationManager.pendingDeepLink = nil
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
