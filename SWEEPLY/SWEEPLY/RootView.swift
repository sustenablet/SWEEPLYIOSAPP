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
    @Environment(NetworkMonitor.self)       private var networkMonitor

    @State private var selectedTab: Tab = .dashboard
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
    @State private var pendingLockTask: Task<Void, Never>? = nil

    @AppStorage("hasSeenIntroOnboarding") private var hasSeenIntroOnboarding = true
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

    enum Tab {
        case dashboard, schedule, clients, finances, business
    }

    private var overdueInvoiceCount: Int {
        invoicesStore.invoices.filter { $0.status == .overdue }.count
    }

    @Environment(\.scenePhase) private var scenePhase
    private let biometricLockDelay: Duration = .seconds(30)

    var body: some View {
        ZStack {
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
            } else if showSignUpFlow {
                OnboardingView(isSignUpFlow: true) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSignUpFlow = false
                    }
                }
                .transition(.move(edge: .trailing))
            } else if !session.isAuthenticated && !getStartedDismissed && !showLoginFlow {
                GetStartedView(
                    onSignUp: {
                        withAnimation(.easeInOut(duration: 0.3)) { showSignUpFlow = true }
                    },
                    onLogIn: {
                        withAnimation(.easeInOut(duration: 0.3)) { showLoginFlow = true }
                    }
                )
                .transition(.move(edge: .leading))
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
            } else if showLoginFlow {
                LoginView(onDismiss: { showLoginFlow = false })
            } else {
                LoginView(onDismiss: nil)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSignUpFlow)
        .animation(.easeInOut(duration: 0.3), value: showLoginFlow)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && biometricLockEnabled {
                scheduleDelayedLock()
            } else if phase == .active {
                cancelDelayedLock()
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
        .onChange(of: biometricLockEnabled) { _, enabled in
            if !enabled {
                cancelDelayedLock()
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
        .onChange(of: networkMonitor.isConnected) { wasConnected, isNowConnected in
            // Reconnected — flush any queued offline writes first, then pull
            // fresh data so remote changes and our optimistic writes are reconciled.
            guard isNowConnected && !wasConnected && session.isAuthenticated else { return }
            Task {
                await SyncQueue.shared.flush()
                async let j: () = jobsStore.load(isAuthenticated: true)
                async let i: () = invoicesStore.load(isAuthenticated: true)
                async let c: () = clientsStore.load(isAuthenticated: true)
                _ = await (j, i, c)
                await invoicesStore.markOverdueInvoices()
                if let uid = session.userId {
                    async let p: () = profileStore.load(userId: uid)
                    async let e: () = expenseStore.load(userId: uid)
                    async let n: () = notificationsStore.load(isAuthenticated: true, userId: uid)
                    _ = await (p, e, n)
                }
            }
        }
    }

    private func scheduleDelayedLock() {
        cancelDelayedLock()
        pendingLockTask = Task {
            try? await Task.sleep(for: biometricLockDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isLocked = true
                pendingLockTask = nil
            }
        }
    }

    private func cancelDelayedLock() {
        pendingLockTask?.cancel()
        pendingLockTask = nil
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
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Sweeply".translated()) { success, _ in
                DispatchQueue.main.async {
                    if success { isLocked = false }
                }
            }
        } else {
            // Fall back to passcode
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Sweeply".translated()) { success, _ in
                DispatchQueue.main.async {
                    if success { isLocked = false }
                }
            }
        }
    }

    private var biometricLockOverlay: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image("LockMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                VStack(spacing: 10) {
                    Text("Sweeply is Locked".translated())
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("Your business data is protected.".translated())
                        .font(.system(size: 17))
                        .foregroundStyle(Color.sweeplyTextSub)
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 48)
            }
        }
        .transition(.opacity)
    }

    private var offlineBanner: some View {
        VStack {
            if !networkMonitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 13, weight: .semibold))
                    Text("No internet connection".translated())
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
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
            .toolbarBackground(.visible, for: .tabBar)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToJob"),
                        object: nil,
                        userInfo: ["jobId": id]
                    )
                }
            case .invoice(let id):
                selectedTab = .finances
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToInvoice"),
                        object: nil,
                        userInfo: ["invoiceId": id]
                    )
                }
            case .schedule:
                selectedTab = .schedule
            case .finances:
                selectedTab = .finances
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
        .overlay(offlineBanner)
    }

    private func applyTabBarAppearance() {
        // Keep reapplication deterministic across sheet/presentation transitions.
        DispatchQueue.main.async {
            applyTabBarAppearanceInternal()
        }
    }
    
    private func applyTabBarAppearanceInternal() {
        // ── Tab bar ──────────────────────────────────────────────────────────
        // iOS 18+/26 renders the tab bar as a floating glass material on top of
        // the warm-stone app background. White-on-navy unselected colors become
        // invisible when the system overrides the configured background — so we
        // use dark adaptive colors that read well on glass *and* any solid bg.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()

        let unselectedColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 0.55)
        tabAppearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: unselectedColor,
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
