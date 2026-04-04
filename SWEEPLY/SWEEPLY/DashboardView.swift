import SwiftUI

struct DashboardView: View {
    @Environment(AppSession.self) private var session
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(NotificationsStore.self) private var notificationsStore

    @State private var appeared = false
    @State private var showProfileMenu = false
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var showPlaybook = true
    @State private var playbookDone: [Bool] = [true, false, false, false]
    @State private var healthStats: HealthStats? = nil
    @State private var selectedHealthSlide = 0

    // MARK: - Derived Properties
    
    private var profile: UserProfile {
        profileStore.profile ?? MockData.profile
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
        invoicesStore.invoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.amount }
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
                title: "Revenue Pulse",
                subtitle: SupabaseManager.isConfigured && session.isAuthenticated ? "Weekly revenue from Supabase-backed jobs" : "Weekly revenue from local store data",
                value: (healthStats?.revenue ?? weekEarned).currency,
                trend: healthStats?.revenue_trend ?? "+18%",
                isPositive: healthStats?.is_rev_positive ?? true,
                icon: "dollarsign",
                iconColor: .sweeplyAccent,
                footnote: "\(completedCount) completed jobs this week"
            ),
            DashboardHealthCardModel(
                title: "Visit Load",
                subtitle: SupabaseManager.isConfigured && session.isAuthenticated ? "Weekly visit count from health RPC" : "Weekly scheduled visit count from local store",
                value: "\(healthStats?.job_count ?? currentWeekJobs.count)",
                trend: healthStats?.job_trend ?? "+5%",
                isPositive: healthStats?.is_job_positive ?? true,
                icon: "calendar",
                iconColor: .sweeplyNavy,
                footnote: "\(todayJobs.count) jobs on today’s board"
            ),
            DashboardHealthCardModel(
                title: "Collections",
                subtitle: "Open invoice balance that still needs attention",
                value: outstandingTotal.currency,
                trend: overdueInvoicesCount == 0 ? "On track" : "\(overdueInvoicesCount) overdue",
                isPositive: overdueInvoicesCount == 0,
                icon: "creditcard",
                iconColor: overdueInvoicesCount == 0 ? .sweeplyAccent : .sweeplyDestructive,
                footnote: "\(ongoingInvoices.count) invoices still open"
            ),
            DashboardHealthCardModel(
                title: "Client Activity",
                subtitle: "Unique clients touched by this week’s scheduled work",
                value: "\(activeClientsThisWeek)",
                trend: activeClientsThisWeek > 0 ? "Active week" : "No activity",
                isPositive: activeClientsThisWeek > 0,
                icon: "person.2",
                iconColor: .blue,
                footnote: "\(clientsStore.clients.count) total clients in the system"
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
                    if showPlaybook && !playbookDone.allSatisfy({ $0 }) {
                        DashboardPlaybook(playbookDone: $playbookDone, showPlaybook: $showPlaybook)
                    }

                    // ── Today's Schedule ─────────────────────────
                    todayScheduleSection

                    // ── Business Health ──────────────────────────
                    businessHealthSection

                    // ── Outstanding Invoices ─────────────────────
                    outstandingInvoicesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
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
            ProfileMenuView(showSettings: $showSettings)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Original Layout Essence Components

    private var headerRow: some View {
        PageHeader(
            eyebrow: nil,
            title: longDate,
            subtitle: "Good morning, \(profile.fullName.split(separator: " ").first ?? "")"
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
                CardHeader(title: "Today's Schedule", action: { /* View All */ })
                
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
                CardHeader(title: "Outstanding Invoices", action: { /* View All */ })
                
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
                            DashInvoiceRow(invoice: invoice, invoicesStore: invoicesStore)
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
        case .inProgress: return Color.blue
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
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.clientName).font(.system(size: 14, weight: .semibold))
                Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12)).foregroundStyle(invoice.status == .overdue ? Color.sweeplyDestructive : Color.sweeplyTextSub)
            }
            Spacer()
            HStack(spacing: 8) {
                Text(invoice.amount.currency).font(.system(size: 14, weight: .bold, design: .monospaced))
                InvoiceStatusBadge(status: invoice.status)
                Button("Mark Paid") { Task { await invoicesStore.markPaid(id: invoice.id) } }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Color.sweeplyNavy).clipShape(Capsule())
            }
        }.padding(.vertical, 10)
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
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
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
    @Binding var playbookDone: [Bool]
    @Binding var showPlaybook: Bool
    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Get started").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { withAnimation { showPlaybook = false } } label: { Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub) }
                }
                VStack(spacing: 12) {
                    PlaybookRow(title: "Add your first client", icon: "person.badge.plus", isDone: playbookDone[0]) { playbookDone[0].toggle() }
                    PlaybookRow(title: "Schedule your first job", icon: "calendar.badge.plus", isDone: playbookDone[1]) { playbookDone[1].toggle() }
                    PlaybookRow(title: "Create your first invoice", icon: "doc.badge.plus", isDone: playbookDone[2]) { playbookDone[2].toggle() }
                    PlaybookRow(title: "Set up business profile", icon: "building.2", isDone: playbookDone[3]) { playbookDone[3].toggle() }
                }
                Text("\(playbookDone.filter { $0 }.count) of 4 complete").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub).padding(.top, 4)
            }
        }
    }
}

struct PlaybookRow: View {
    let title: String; let icon: String; let isDone: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(isDone ? Color.sweeplyAccent : Color.sweeplyBorder)
                Text(title).font(.system(size: 14)).foregroundStyle(isDone ? Color.sweeplyTextSub : Color.primary).strikethrough(isDone)
                Spacer()
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
            }
        }.buttonStyle(.plain)
    }
}

struct ProfileMenuView: View {
    @Environment(AppSession.self) private var session
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @Binding var showSettings: Bool
    
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
