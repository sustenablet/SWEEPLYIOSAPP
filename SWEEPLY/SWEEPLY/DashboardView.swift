import SwiftUI
import Charts

private let inProgressColor = Color(red: 0.4, green: 0.45, blue: 0.95)

struct DashboardView: View {
    var onViewAllSchedule: (() -> Void)? = nil
    var onViewAllFinances: (() -> Void)? = nil

    @Environment(AppSession.self) private var session
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(TeamStore.self) private var teamStore

    @State private var appeared = false
    @State private var showProfileMenu = false
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var selectedInvoiceId: UUID? = nil
    @State private var showInvoiceDetail = false
    @State private var showTeam = false
    /// User hid the checklist after completing all steps (persisted).
    @AppStorage("dashboardPlaybookPermanentlyHidden") private var playbookPermanentlyHidden = false
    @State private var healthStats: HealthStats? = nil
    @State private var selectedHealthSlide = 0

    // MARK: - Get Started State

    private var playbookDone: [Bool] {
        [
            !clientsStore.clients.isEmpty,
            !jobsStore.jobs.isEmpty,
            !invoicesStore.invoices.isEmpty,
            profileIsComplete
        ]
    }

    private var profileIsComplete: Bool {
        guard let p = profileStore.profile else { return false }
        return !p.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !p.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Derived Properties
    
    private var profile: UserProfile {
        profileStore.profile ?? MockData.profile
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var notificationsCount: Int {
        notificationsStore.notifications.filter { !$0.isRead }.count
    }

    private var initials: String {
        profile.fullName
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
    }

    private var longDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var todayJobs: [Job] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return jobsStore.jobs.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    private var completedCount: Int {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return jobsStore.jobs.filter { $0.date >= start && $0.status == .completed }.count
    }

    private var weekEarned: Double {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return jobsStore.jobs
            .filter { $0.date >= start && $0.status == .completed }
            .reduce(0) { $0 + $1.price }
    }

    private var outstandingTotal: Double {
        invoicesStore.invoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.total }
    }

    private var ongoingInvoices: [Invoice] {
        invoicesStore.invoices
            .filter { $0.status != .paid }
            .sorted { a, b in
                if a.status == .overdue && b.status != .overdue { return true }
                if b.status == .overdue && a.status != .overdue { return false }
                return a.dueDate < b.dueDate
            }
    }

    private var currentWeekJobs: [Job] {
        let calendar = Calendar.current
        return jobsStore.jobs.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }
    }

    private var activeClientsThisWeek: Int {
        Set(currentWeekJobs.map(\.clientId)).count
    }

    private var overdueInvoicesCount: Int {
        invoicesStore.invoices.filter { $0.status == .overdue }.count
    }

    private var healthCards: [DashboardHealthCardModel] {
        [
            DashboardHealthCardModel(
                title: "Weekly Revenue",
                subtitle: "Total earned from completed jobs this week",
                value: (healthStats?.revenue ?? weekEarned).currency,
                trend: healthStats?.revenue_trend ?? "+18%",
                isPositive: healthStats?.is_rev_positive ?? true,
                icon: "dollarsign",
                iconColor: .sweeplyAccent,
                footnote: "\(completedCount) jobs completed this week"
            ),
            DashboardHealthCardModel(
                title: "Weekly Jobs",
                subtitle: "Jobs scheduled and completed this week",
                value: "\(healthStats?.job_count ?? currentWeekJobs.count)",
                trend: healthStats?.job_trend ?? "+5%",
                isPositive: healthStats?.is_job_positive ?? true,
                icon: "calendar",
                iconColor: .sweeplyNavy,
                footnote: "\(todayJobs.count) on today’s schedule"
            ),
            DashboardHealthCardModel(
                title: "Outstanding Balance",
                subtitle: "Invoices sent that haven’t been paid yet",
                value: outstandingTotal.currency,
                trend: overdueInvoicesCount == 0 ? "All on track" : "\(overdueInvoicesCount) overdue",
                isPositive: overdueInvoicesCount == 0,
                icon: "creditcard",
                iconColor: overdueInvoicesCount == 0 ? .sweeplyAccent : .sweeplyDestructive,
                footnote: "\(ongoingInvoices.count) open invoice\(ongoingInvoices.count == 1 ? "" : "s")"
            ),
            DashboardHealthCardModel(
                title: "Active Clients",
                subtitle: "Clients with visits scheduled this week",
                value: "\(activeClientsThisWeek)",
                trend: activeClientsThisWeek > 0 ? "Active week" : "Quiet week",
                isPositive: activeClientsThisWeek > 0,
                icon: "person.2",
                iconColor: .sweeplyNavy,
                footnote: "\(clientsStore.clients.count) total client\(clientsStore.clients.count == 1 ? "" : "s") on your roster"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ───────────────────────────────────────
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                Divider()

                // ── Dashboard Hero (Revenue + Stats Grid) ───────────
                HStack(alignment: .center, spacing: 20) {
                    revenueHero
                    
                    statsGrid
                        .frame(width: 140)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.bottom, 24)

                // ── Sub-sections with spacing ────────────────────
                VStack(spacing: 12) {
                    // ── Getting Started checklist ────────────────
                    if !playbookPermanentlyHidden {
                        DashboardPlaybook(
                            playbookDone: playbookDone,
                            permanentlyHidden: $playbookPermanentlyHidden
                        )
                    }

                    // ── Today's Schedule ─────────────────────────
                    todayScheduleSection

                    // ── Business Health ──────────────────────────
                    businessHealthSection

                    // ── Outstanding Invoices ─────────────────────
                    outstandingInvoicesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { appeared = true }
                Task {
                    await notificationsStore.load(isAuthenticated: session.isAuthenticated, userId: session.userId)
                    if let uid = session.userId {
                        healthStats = await jobsStore.fetchHealthStats(userId: uid)
                    }
                }
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .sheet(isPresented: $showProfileMenu) {
            ProfileMenuView(showSettings: $showSettings, showTeam: $showTeam)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTeam) {
            TeamView()
                .environment(teamStore)
                .environment(profileStore)
                .environment(session)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showInvoiceDetail) {
            if let id = selectedInvoiceId {
                NavigationStack {
                    InvoiceDetailView(invoiceId: id)
                }
                .environment(invoicesStore)
                .environment(clientsStore)
                .environment(profileStore)
                .environment(session)
            }
        }
        .onChange(of: showSettings) { _, isShowing in
            if !isShowing {
                // Re-apply tab bar after full-screen cover is dismissed (iOS resets it)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshTabBar"), object: nil)
                }
            }
        }
    }

    // MARK: - Original Layout Essence Components

    private var headerRow: some View {
        PageHeader(
            eyebrow: nil,
            title: longDate,
            subtitle: "\(greeting), \(profile.fullName.split(separator: " ").first ?? "")"
        ) {
            HStack(spacing: 12) {
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 40, height: 40)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            if notificationsCount > 0 {
                                Circle()
                                    .fill(Color.sweeplyDestructive)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .buttonStyle(.plain)

                Button { showProfileMenu = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.sweeplyNavy)
                            .frame(width: 40, height: 40)
                        Text(initials)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 8 weeks of paid invoice revenue grouped by week start
    private var weeklyRevenueData: [(week: Date, amount: Double)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<8).reversed().compactMap { weeksAgo -> (Date, Double)? in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: cal.startOfDay(for: today)),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
            let total = invoicesStore.invoices
                .filter { $0.status == .paid && $0.createdAt >= weekStart && $0.createdAt < weekEnd }
                .reduce(0.0) { $0 + $1.subtotal }
            return (weekStart, total)
        }
    }

    private var revenueHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REVENUE THIS WEEK")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            Text(weekEarned.currency)
                .font(.system(size: 42, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .tracking(-1.5)

            if completedCount > 0 {
                Text("\(completedCount) job\(completedCount == 1 ? "" : "s") completed")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            } else {
                Text("No completed jobs yet this week")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            // Mini area sparkline — last 8 weeks
            if !weeklyRevenueData.isEmpty {
                Chart(weeklyRevenueData, id: \.week) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        y: .value("Revenue", point.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sweeplyAccent.opacity(0.3), Color.sweeplyAccent.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Revenue", point.amount)
                    )
                    .foregroundStyle(Color.sweeplyAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
                .animation(.easeOut(duration: 0.6), value: weeklyRevenueData.map(\.amount))
                .padding(.top, 4)
            }
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            DashStatBox(value: "\(clientsStore.clients.count)", label: "Clients")
            DashStatBox(value: "\(jobsStore.jobs.filter { $0.status == .scheduled }.count)", label: "Scheduled")
            DashStatBox(value: "\(todayJobs.filter { $0.status == .scheduled || $0.status == .inProgress}.count)", label: "Left")
            DashStatBox(value: outstandingTotal.currency, label: "Due")
        }
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // MARK: - Premium Wrapper Sections

    private var todayScheduleSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Today's Schedule", action: onViewAllSchedule)
                
                if todayJobs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                        Text("No jobs scheduled for today")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(todayJobs.enumerated()), id: \.element.id) { index, job in
                    DashJobRow(job: job, jobsStore: jobsStore)
                    if index < todayJobs.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
                }
            }
        }
    }

    private var businessHealthSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Business Health", subtitle: "Swipe through your operating metrics", action: nil)

                TabView(selection: $selectedHealthSlide) {
                    ForEach(Array(healthCards.enumerated()), id: \.offset) { index, card in
                        DashboardHealthSlide(card: card)
                            .tag(index)
                            .padding(.vertical, 2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 178)

                HStack(spacing: 8) {
                    ForEach(healthCards.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedHealthSlide ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.8))
                            .frame(width: index == selectedHealthSlide ? 18 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: selectedHealthSlide)
                    }
                    Spacer()
                    Text("\(selectedHealthSlide + 1) / \(healthCards.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }

    private var outstandingInvoicesSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Outstanding Invoices", action: onViewAllFinances)
                
                if ongoingInvoices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sweeplyAccent.opacity(0.4))
                        Text("All caught up!")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(ongoingInvoices.prefix(3).enumerated()), id: \.element.id) { index, invoice in
                            DashInvoiceRow(invoice: invoice, invoicesStore: invoicesStore) {
                                selectedInvoiceId = invoice.id
                                showInvoiceDetail = true
                            }
                            if index < min(ongoingInvoices.count, 3) - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct DashStatBox: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

struct DashJobRow: View {
    let job: Job
    let jobsStore: JobsStore
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(timeStr).font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(amPm).font(.system(size: 10)).foregroundStyle(Color.sweeplyTextSub)
            }.frame(width: 36, alignment: .trailing)
            Circle().fill(statusColor).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(job.clientName).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(job.price.currency).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Menu {
                        Button("Start Job", systemImage: "play.fill") { Task { await jobsStore.updateStatus(id: job.id, status: .inProgress) } }
                        Button("Mark Complete", systemImage: "checkmark") { Task { await jobsStore.updateStatus(id: job.id, status: .completed) } }
                        Button("Cancel Job", systemImage: "xmark", role: .destructive) { Task { await jobsStore.updateStatus(id: job.id, status: .cancelled) } }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Color.sweeplyTextSub).padding(.leading, 8) }
                }
                Text("\(job.serviceType.rawValue) · \(durationStr) · \(job.address)").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub).lineLimit(1)
            }
        }.padding(.vertical, 10)
    }
    private var timeStr: String { let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: job.date) }
    private var amPm: String { let f = DateFormatter(); f.dateFormat = "a"; return f.string(from: job.date).uppercased() }
    private var statusColor: Color {
        switch job.status {
        case .completed:  return Color.sweeplyAccent
        case .inProgress: return inProgressColor
        case .scheduled:  return Color.sweeplyTextSub.opacity(0.5)
        case .cancelled:  return Color.sweeplyDestructive
        }
    }
    private var durationStr: String {
        let h = Int(job.duration); let m = Int((job.duration - Double(h)) * 60)
        return h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
    }
}

struct DashInvoiceRow: View {
    let invoice: Invoice
    let invoicesStore: InvoicesStore
    var onTap: (() -> Void)? = nil
    var body: some View {
        Button(action: { onTap?() }) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(invoice.clientName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.sweeplyNavy)
                    Text(invoice.status == .overdue
                        ? "Overdue since \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))"
                        : "Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))"
                    )
                    .font(.system(size: 12)).foregroundStyle(invoice.status == .overdue ? Color.sweeplyDestructive : Color.sweeplyTextSub)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text(invoice.total.currency).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Color.sweeplyNavy)
                    Button("Mark Paid") { Task { await invoicesStore.markPaid(id: invoice.id) } }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Color.sweeplyNavy).clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
    }
}

struct DashboardHealthCardModel {
    let title: String
    let subtitle: String
    let value: String
    let trend: String
    let isPositive: Bool
    let icon: String
    let iconColor: Color
    let footnote: String
}

struct DashboardHealthSlide: View {
    let card: DashboardHealthCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(card.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Spacer()
                    TrendBadge(value: card.trend, isPositive: card.isPositive)
                }
                Text(card.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(2)
            }

            Text(card.value)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(card.footnote)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct TrendBadge: View {
    let value: String; let isPositive: Bool
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .bold))
            Text(value).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isPositive ? Color.sweeplyAccent : Color.sweeplyDestructive)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background((isPositive ? Color.sweeplyAccent : Color.sweeplyDestructive).opacity(0.1)).clipShape(Capsule())
    }
}

struct DashboardPlaybook: View {
    let playbookDone: [Bool]
    @Binding var permanentlyHidden: Bool

    /// While steps are incomplete: collapsed strip vs full card. Persisted.
    @AppStorage("dashboardPlaybookExpanded") private var playbookExpanded = true

    @State private var showClientForm = false
    @State private var showJobForm = false
    @State private var showInvoiceForm = false
    @State private var showSettings = false

    private var doneCount: Int { playbookDone.filter { $0 }.count }
    private var allDone: Bool { playbookDone.count == 4 && playbookDone.allSatisfy { $0 } }

    var body: some View {
        Group {
            if allDone {
                completionCard
            } else if playbookExpanded {
                expandedCard
            } else {
                compactBar
            }
        }
        .sheet(isPresented: $showClientForm) { NewClientForm() }
        .sheet(isPresented: $showJobForm) { NewJobForm() }
        .sheet(isPresented: $showInvoiceForm) { NewInvoiceView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var expandedCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get started")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("\(doneCount) of 4 complete")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.28)) { playbookExpanded = false }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Collapse get started")
                }

                Text("Finish every step before you can remove this section.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.9))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sweeplyBorder)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sweeplyAccent)
                            .frame(
                                width: geo.size.width * CGFloat(doneCount) / 4.0,
                                height: 4
                            )
                            .animation(.easeInOut(duration: 0.4), value: doneCount)
                    }
                }
                .frame(height: 4)

                VStack(spacing: 10) {
                    PlaybookRow(title: "Add your first client", icon: "person.badge.plus", isDone: playbookDone[0]) {
                        if !playbookDone[0] { showClientForm = true }
                    }
                    PlaybookRow(title: "Schedule your first job", icon: "calendar.badge.plus", isDone: playbookDone[1]) {
                        if !playbookDone[1] { showJobForm = true }
                    }
                    PlaybookRow(title: "Create your first invoice", icon: "doc.badge.plus", isDone: playbookDone[2]) {
                        if !playbookDone[2] { showInvoiceForm = true }
                    }
                    PlaybookRow(title: "Set up business profile", icon: "building.2", isDone: playbookDone[3]) {
                        if !playbookDone[3] { showSettings = true }
                    }
                }
            }
        }
    }

    private var compactBar: some View {
        Button {
            withAnimation(.spring(duration: 0.28)) { playbookExpanded = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get started")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("\(doneCount) of 4 complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand get started")
    }

    private var completionCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You're all set")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Every onboarding step is complete.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            permanentlyHidden = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Hide get started")
                }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.sweeplySuccess)
                    Text("4 of 4 complete")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
}

struct PlaybookRow: View {
    let title: String
    let icon: String
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isDone ? Color.sweeplyAccent : Color.sweeplyAccent.opacity(0.08))
                        .frame(width: 32, height: 32)
                    Image(systemName: isDone ? "checkmark" : icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isDone ? .white : Color.sweeplyAccent)
                }
                Text(title)
                    .font(.system(size: 14, weight: isDone ? .regular : .medium))
                    .foregroundStyle(isDone ? Color.sweeplyTextSub : Color.sweeplyNavy)
                Spacer()
                if !isDone {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isDone ? 0.6 : 1.0)
    }
}

struct ProfileMenuView: View {
    @Environment(AppSession.self) private var session
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @Binding var showSettings: Bool
    @Binding var showTeam: Bool
    
    private var profile: UserProfile { profileStore.profile ?? MockData.profile }
    
    var body: some View {
        VStack(spacing: 24) {
            // Branded Identity Card
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.sweeplyNavy.gradient).frame(width: 80, height: 80)
                    Text(initials).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                }
                VStack(spacing: 4) {
                    Text(profile.fullName).font(.system(size: 20, weight: .bold))
                    Text(profile.email).font(.system(size: 14)).foregroundStyle(Color.sweeplyTextSub)
                    Text(profile.businessName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.sweeplyAccent).padding(.top, 4)
                }
            }
            .padding(.top, 32)
            
            Divider()
            
            // Actions
            VStack(spacing: 8) {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showSettings = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.sweeplyBorder)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showTeam = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                        Text("My Team")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.sweeplyBorder)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                Button {
                    Task { await session.signOut(); dismiss() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                        Spacer()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.sweeplyDestructive)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.sweeplySurface)
    }
    
    private var initials: String {
        profile.fullName.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
    }
}
