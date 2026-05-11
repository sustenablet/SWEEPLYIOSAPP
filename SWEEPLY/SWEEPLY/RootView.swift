import SwiftUI
import LocalAuthentication

struct RootView: View {
    @Environment(AppSession.self)           private var session
    @Environment(ClientsStore.self)         private var clientsStore
    @Environment(JobsStore.self)            private var jobsStore
    @Environment(InvoicesStore.self)        private var invoicesStore
    @Environment(ProfileStore.self)         private var profileStore
    @Environment(NotificationManager.self)  private var notificationManager
    @Environment(NotificationsStore.self)   private var notificationsStore
    @Environment(TeamStore.self)            private var teamStore
    @Environment(ExpenseStore.self)         private var expenseStore
    @Environment(SubscriptionManager.self)  private var subscriptionManager

    @State private var selectedTab: Tab = .dashboard
    @State private var deepLinkedJobId: UUID? = nil
    @State private var deepLinkedInvoiceId: UUID? = nil
    @State private var showNewJob = false
    @State private var showNewClient = false
    @State private var showNewInvoice = false
    @State private var showQuickAdd = false
    @State private var showOnboarding = false
    @State private var showSignUpFlow = false
    @State private var showLoginFlow = false
    @State private var isLocked = false
    @State private var minimumSplashElapsed = false
    @State private var showIntroOnboarding = false
    @State private var getStartedDismissed = false
    @State private var notificationRefreshTrigger = 0
    @State private var lastNotificationRefresh = Date.distantPast

    @AppStorage("hasSeenIntroOnboarding") private var hasSeenIntroOnboarding = true
    @AppStorage("lastKnownIsProPlan")      private var lastKnownIsProPlan = false
    @AppStorage("newFeatureDot_revenueBar")  private var dotRevenueBar  = false
    @AppStorage("newFeatureDot_reports")     private var dotReports     = false
    @AppStorage("newFeatureDot_teamBanner")  private var dotTeamBanner  = false
    // Observing appLanguage forces the entire view hierarchy to re-render on language change,
    // so all .translated() calls pick up the new language immediately.
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled: Bool = false
    @AppStorage("pendingShortcut") private var pendingShortcut: String = ""
    @AppStorage("pendingSpotlightLink") private var pendingSpotlightLink: String = ""
    @AppStorage("pendingScheduleDate") private var pendingScheduleDate: String = ""
    @State private var lastTabBarApplyTime: Date = .distantPast
    private let tabBarApplyCooldown: TimeInterval = 0.5

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
            } else if !session.hasResolvedInitialSession || !minimumSplashElapsed {
                SplashView()
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        minimumSplashElapsed = true
                    }
            } else if showIntroOnboarding || !hasSeenIntroOnboarding {
                IntroOnboardingView {
                    hasSeenIntroOnboarding = true
                    showIntroOnboarding = false
                }
            } else if !session.isAuthenticated && !getStartedDismissed && !showSignUpFlow && !showLoginFlow {
                GetStartedView(
                    onSignUp: { showSignUpFlow = true },
                    onLogIn:  { showLoginFlow  = true }
                )
            } else if session.isAuthenticated {
                ZStack {
                    switch session.currentViewMode {
                    case .ownBusiness:
                        mainTabs
                            .id(appLanguage)
                    case .memberOf(let membership):
                        CleanerRootView(membership: membership)
                            .id(appLanguage)
                    }
                    if isLocked {
                        biometricLockOverlay
                    }
                }
                .sheet(isPresented: Binding(
                    get: {
                        if case .expired = subscriptionManager.accessLevel,
                           !subscriptionManager.isLoading { return true }
                        return false
                    },
                    set: { _ in }
                )) {
                    SubscriptionPaywallView()
                        .interactiveDismissDisabled()
                }
            } else if showSignUpFlow {
                OnboardingView(isSignUpFlow: true) {
                    showSignUpFlow = false
                }
            } else if showLoginFlow {
                AuthView(onDismiss: { showLoginFlow = false })
            } else {
                AuthView(onDismiss: nil)
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && biometricLockEnabled {
                isLocked = true
            } else if phase == .active {
                applyTabBarAppearance()
                if isLocked {
                    authenticate()
                } else {
                    handlePendingActions()
                }
                if session.isAuthenticated {
                    Task { await refreshNotificationsWithDebounce() }
                }
            }
        }
        .onChange(of: notificationRefreshTrigger) { _, _ in
            if session.isAuthenticated {
                Task {
                    await notificationsStore.load(
                        isAuthenticated: session.isAuthenticated,
                        userId: session.userId
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewNotificationsArrived"))) { _ in
            notificationRefreshTrigger += 1
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

    private func handlePendingActions() {
        guard session.isAuthenticated, session.hasResolvedInitialSession else { return }
        if !pendingScheduleDate.isEmpty { handlePendingScheduleDate() }
        if !pendingShortcut.isEmpty     { handlePendingShortcut() }
        if !pendingSpotlightLink.isEmpty { handleSpotlightLink() }
    }

    private func handlePendingScheduleDate() {
        let dateStr = pendingScheduleDate
        pendingScheduleDate = ""
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        if let date = f.date(from: dateStr) {
            selectedTab = .schedule
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToScheduleDate"),
                    object: nil,
                    userInfo: ["date": date]
                )
            }
        } else {
            selectedTab = .schedule
        }
    }

    private func handlePendingShortcut() {
        let shortcut = pendingShortcut
        pendingShortcut = ""
        switch shortcut {
        case "com.sweeply.newjob":
            showNewJob = true
        case "com.sweeply.schedule":
            selectedTab = .schedule
        default:
            break
        }
    }

    private func refreshNotificationsWithDebounce() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNotificationRefresh)
        if elapsed >= 5 {
            lastNotificationRefresh = now
            notificationRefreshTrigger += 1
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
                    Text("Sweeply is Locked".translated())
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Your business data is protected.".translated())
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
                        Text("Unlock Sweeply".translated())
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
                DashboardView(
                    onViewAllSchedule: { selectedTab = .schedule },
                    onViewAllFinances: { selectedTab = .finances }
                )
                    .tabItem { Label("Dashboard".translated(), systemImage: "square.grid.2x2.fill") }
                    .tag(Tab.dashboard)

                ScheduleView()
                    .tabItem { Label("Schedule".translated(), systemImage: "calendar") }
                    .tag(Tab.schedule)

                ClientsView()
                    .tabItem { Label("Clients".translated(), systemImage: "person.2.fill") }
                    .tag(Tab.clients)

                FinancesView()
                    .tabItem { Label("Finances".translated(), systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(Tab.finances)
                    .badge(overdueInvoiceCount > 0 ? overdueInvoiceCount : 0)

                BusinessView()
                    .tabItem { Label("Business".translated(), systemImage: "building.2.fill") }
                    .tag(Tab.business)
            }
            .tint(Color.sweeplyAccent)
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            applyTabBarAppearance()
        }

        if selectedTab != .schedule {
            FABView(
                selectedTab: $selectedTab,
                onNewJob: { showNewJob = true },
                onNewClient: { showNewClient = true },
                onNewInvoice: { showNewInvoice = true }
            )
        }
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
            OnboardingView(isSignUpFlow: false, onDismiss: nil)
        }
        .onChange(of: showOnboarding) { _, _ in }
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
                await teamStore.load(ownerId: uid)
                await expenseStore.load(userId: uid)
                await notificationsStore.load(isAuthenticated: true, userId: uid)
                
                // Trigger business onboarding for new users who haven't set up their profile
                let businessName = profileStore.profile?.businessName ?? ""
                if businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showOnboarding = true
                    }
                }
            }
            await clientsStore.load(isAuthenticated: session.isAuthenticated)
            WidgetDataWriter.write(jobs: jobsStore.jobs, invoices: invoicesStore.invoices)
        }
        .onChange(of: session.currentViewMode) { _, _ in
            Task { await jobsStore.load(isAuthenticated: session.isAuthenticated) }
        }
        .onChange(of: subscriptionManager.isPro) { wasPro, isPro in
            if isPro && !wasPro {
                // User just upgraded to Pro — light up all new-feature dots
                dotRevenueBar = true
                dotReports    = true
                dotTeamBanner = true
            }
            lastKnownIsProPlan = isPro
        }
        .onChange(of: session.isAuthenticated) { _, authed in
            if authed {
                // Auth just resolved — handle any shortcuts/deep links that arrived early
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    handlePendingActions()
                }
            } else {
                clientsStore.clear()
                jobsStore.clear()
                invoicesStore.clear()
                profileStore.clear()
                teamStore.clear()
                expenseStore.clear()
                getStartedDismissed = false
                showSignUpFlow = false
                showLoginFlow = false
            }
        }
        // Rebuild pay-day reminders whenever jobs or team members change
        .onChange(of: jobsStore.jobs.count) { _, _ in
            notificationManager.schedulePayReminders(jobs: jobsStore.jobs, members: teamStore.members)
        }
        .onChange(of: teamStore.members.count) { _, _ in
            notificationManager.schedulePayReminders(jobs: jobsStore.jobs, members: teamStore.members)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshTabBar"))) { _ in
            applyTabBarAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HandleShortcutItem"))) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            pendingShortcut = ""  // clear any stale UserDefaults value
            switch type {
            case "com.sweeply.newjob":    showNewJob = true
            case "com.sweeply.schedule":  selectedTab = .schedule
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MarkJobComplete"))) { notification in
            if let jobId = notification.userInfo?["jobId"] as? UUID {
                Task {
                    await jobsStore.updateStatus(id: jobId, status: .completed)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MarkInvoicePaid"))) { notification in
            if let invoiceId = notification.userInfo?["invoiceId"] as? UUID,
               let invoice = invoicesStore.invoices.first(where: { $0.id == invoiceId }) {
                Task {
                    await invoicesStore.markPaid(id: invoiceId, amount: invoice.total, method: .cash)
                }
            }
        }
        .onAppear {
            applyTabBarAppearance()
        }
    }

    private func applyTabBarAppearance() {
        // Debounce rapid calls to prevent race conditions
        let now = Date()
        guard now.timeIntervalSince(lastTabBarApplyTime) > tabBarApplyCooldown else { return }
        lastTabBarApplyTime = now
        
        DispatchQueue.main.async {
            applyTabBarAppearanceInternal()
        }
    }
    
    private func applyTabBarAppearanceInternal() {
        // ── Tab bar ──────────────────────────────────────────────────────────
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Color.sweeplyNavy)

        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 1, alpha: 0.35)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(white: 1, alpha: 0.35),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        let accentUIColor = UIColor(Color.sweeplyAccent)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = accentUIColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: accentUIColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        UITabBar.appearance().standardAppearance   = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // ── Navigation bar (global) ──────────────────────────────────────────
        // Always use hardcoded light-mode values — the app is light-only but
        // sheets/covers don't inherit preferredColorScheme(.light) from RootView.
        // Using adaptive UIColor(Color.sweeplyNavy) would resolve to near-black
        // in dark mode, making icons invisible against the dark nav bar.
        let navBg    = UIColor(red: 0.965, green: 0.961, blue: 0.945, alpha: 1.0) // sweeplyBackground light
        let navTitle = UIColor(red: 0.15,  green: 0.15,  blue: 0.18,  alpha: 1.0) // sweeplyNavy light
        let navBorder = UIColor(red: 0.88, green: 0.87,  blue: 0.85,  alpha: 0.6) // sweeplyBorder light

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = navBg
        navAppearance.shadowColor = navBorder
        navAppearance.titleTextAttributes = [
            .foregroundColor: navTitle,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: navTitle,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance   = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance    = navAppearance
        // tintColor drives Image(systemName:) icon color in toolbar items
        UINavigationBar.appearance().tintColor = navTitle
    }

    /// Notion-style 5-page product tour once per install, after auth (and after profile onboarding if shown).
}

#Preview {
    RootView()
        .environment(AppSession())
        .environment(ClientsStore())
}
