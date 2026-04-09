import SwiftUI
import Combine

struct BusinessView: View {
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self)  private var profileStore

    @State private var appeared = false
    @State private var showServiceCatalog = false
    @State private var selectedSnapshotSlide = 0
    @State private var showAIChat = false
    @State private var insightIndex = 0

    private var profile: UserProfile {
        profileStore.profile ?? MockData.profile
    }

    private var businessJobs: [Job] {
        jobsStore.jobs
    }

    private var businessInvoices: [Invoice] {
        invoicesStore.invoices
    }

    private var totalRevenue: Double {
        businessInvoices
            .filter { $0.status == .paid }
            .reduce(0) { $0 + $1.total }
    }

    private var outstandingRevenue: Double {
        businessInvoices
            .filter { $0.status != .paid }
            .reduce(0) { $0 + $1.total }
    }

    private var monthlyJobs: [Job] {
        let calendar = Calendar.current
        return businessJobs.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var completedJobsThisMonth: Int {
        monthlyJobs.filter { $0.status == .completed }.count
    }

    private var upcomingJobs: [Job] {
        businessJobs
            .filter { $0.date >= Date() && $0.status != .cancelled }
            .sorted { $0.date < $1.date }
    }

    private var activeClientsCount: Int {
        Set(monthlyJobs.map(\.clientId)).count
    }

    private var averageTicket: Double {
        guard completedJobsThisMonth > 0 else { return 0 }
        let completedRevenue = monthlyJobs
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.price }
        return completedRevenue / Double(completedJobsThisMonth)
    }

    private var monthlyEarned: Double {
        monthlyJobs.filter { $0.status == .completed }.reduce(0) { $0 + $1.price }
    }

    private var upcomingPipelineValue: Double {
        upcomingJobs.reduce(0) { $0 + $1.price }
    }

    private var recurringJobsThisMonth: Int {
        monthlyJobs.filter { $0.isRecurring }.count
    }

    private var totalActiveClients: Int {
        clientsStore.clients.filter { $0.isActive }.count
    }

    private var nextJob: Job? {
        upcomingJobs.first
    }

    private var rotatingInsights: [AIInsight] {
        var items: [AIInsight] = []
        let cal = Calendar.current

        // 1. Average job price (all completed jobs)
        let allCompleted = businessJobs.filter { $0.status == .completed }
        if !allCompleted.isEmpty {
            let avg = allCompleted.reduce(0.0) { $0 + $1.price } / Double(allCompleted.count)
            items.append(AIInsight(
                icon: "dollarsign.circle.fill",
                text: "Your average job is \(avg.currency) based on \(allCompleted.count) completed clean\(allCompleted.count == 1 ? "" : "s")"
            ))
        }

        // 2. Busiest day of week (all-time)
        let dayGroups = Dictionary(grouping: businessJobs) { cal.component(.weekday, from: $0.date) }
        if let busiest = dayGroups.max(by: { $0.value.count < $1.value.count }) {
            let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let name = busiest.key < dayNames.count ? dayNames[busiest.key] : "that day"
            items.append(AIInsight(
                icon: "star.fill",
                text: "\(name) is your busiest day — \(busiest.value.count) job\(busiest.value.count == 1 ? "" : "s") historically"
            ))
        }

        // 3. Most booked service type (all-time)
        let serviceGroups = Dictionary(grouping: businessJobs) { $0.serviceType.rawValue }
        if let top = serviceGroups.max(by: { $0.value.count < $1.value.count }) {
            items.append(AIInsight(
                icon: "sparkles",
                text: "\(top.key) is your most requested service — booked \(top.value.count) time\(top.value.count == 1 ? "" : "s")"
            ))
        }

        // 4. Client re-engagement opportunity (30+ days inactive)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentClientIds = Set(businessJobs.filter { $0.date >= thirtyDaysAgo }.map { $0.clientId })
        let inactive = clientsStore.clients.filter { $0.isActive && !recentClientIds.contains($0.id) }
        if !inactive.isEmpty {
            if inactive.count == 1, let client = inactive.first {
                items.append(AIInsight(
                    icon: "person.badge.clock.fill",
                    text: "\(client.name) hasn't had a booking in 30+ days — a good time to reach out"
                ))
            } else {
                items.append(AIInsight(
                    icon: "person.badge.clock.fill",
                    text: "\(inactive.count) clients haven't booked in 30+ days — a re-engagement opportunity"
                ))
            }
        }

        // 5. Month-over-month revenue change
        if let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) {
            let thisM = businessInvoices.filter {
                $0.status == .paid && cal.isDate($0.createdAt, equalTo: Date(), toGranularity: .month)
            }.reduce(0.0) { $0 + $1.total }
            let lastM = businessInvoices.filter {
                $0.status == .paid && cal.isDate($0.createdAt, equalTo: lastMonthDate, toGranularity: .month)
            }.reduce(0.0) { $0 + $1.total }
            if lastM > 0 {
                let pct = ((thisM - lastM) / lastM) * 100
                let dir = pct >= 0 ? "up" : "down"
                items.append(AIInsight(
                    icon: pct >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                    text: "Revenue is \(dir) \(Int(abs(pct)))% vs last month (\(lastM.currency) → \(thisM.currency))",
                    isWarning: pct < -20,
                    isSuccess: pct > 0
                ))
            }
        }

        // 6. Projected monthly revenue at current pace
        let dayOfMonth = cal.component(.day, from: Date())
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        if dayOfMonth > 5 && monthlyEarned > 0 {
            let projected = (monthlyEarned / Double(dayOfMonth)) * Double(daysInMonth)
            items.append(AIInsight(
                icon: "chart.line.uptrend.xyaxis.circle.fill",
                text: "At this pace you're on track for ~\(projected.currency) this month (\(monthlyEarned.currency) earned so far)",
                isSuccess: true
            ))
        }

        return items
    }

    private var serviceMix: [(label: String, percentage: Double, count: Int)] {
        let grouped = Dictionary(grouping: monthlyJobs, by: \.serviceType)
        let total = max(monthlyJobs.count, 1)

        return grouped.compactMap { service, jobs in
            let count = jobs.count
            guard count > 0 else { return nil }
            return (service.rawValue, Double(count) / Double(total), count)
        }
        .sorted { $0.count > $1.count }
    }

    private var topClients: [(name: String, jobs: Int, revenue: Double)] {
        let grouped = Dictionary(grouping: monthlyJobs, by: \.clientId)

        return grouped.compactMap { _, jobs in
            guard let first = jobs.first else { return nil }
            return (
                name: first.clientName,
                jobs: jobs.count,
                revenue: jobs.reduce(0) { $0 + $1.price }
            )
        }
        .sorted { lhs, rhs in
            if lhs.jobs == rhs.jobs {
                return lhs.revenue > rhs.revenue
            }
            return lhs.jobs > rhs.jobs
        }
    }

    private var catalogServices: [BusinessService] {
        profile.settings.hydratedServiceCatalog
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                PageHeader(
                    eyebrow: profile.businessName.isEmpty ? "Business" : profile.businessName.uppercased(),
                    title: "Operational Overview",
                    subtitle: nil
                )
                .padding(.top, 16)

                // 1. Performance KPIs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        KPIBlock(title: "Active Clients", value: "\(activeClientsCount)", icon: "person.2.fill")
                        KPIBlock(title: "Jobs This Month", value: "\(monthlyJobs.count)", icon: "briefcase.fill")
                        KPIBlock(title: "Collected", value: totalRevenue.currency, icon: "dollarsign.circle.fill")
                        KPIBlock(title: "Scheduled", value: "\(upcomingJobs.count)", icon: "calendar")
                        KPIBlock(title: "Outstanding", value: outstandingRevenue.currency, icon: "exclamationmark.triangle.fill")
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)

                // 2. AI Preview
                aiPreviewSection

                // 3. Snapshot
                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: "Business Snapshot", subtitle: "How the operation is moving this month", action: nil)

                        TabView(selection: $selectedSnapshotSlide) {
                            // Slide 1 — Monthly Operations
                            VStack(alignment: .leading, spacing: 14) {
                                Divider()
                                snapshotRow(
                                    title: "Completed Jobs",
                                    value: "\(completedJobsThisMonth)",
                                    detail: "\(max(0, monthlyJobs.count - completedJobsThisMonth)) still in flight",
                                    accent: .sweeplyAccent
                                )
                                Divider()
                                snapshotRow(
                                    title: "Average Ticket",
                                    value: averageTicket.currency,
                                    detail: "Based on completed visits this month",
                                    accent: .sweeplyNavy
                                )
                                Divider()
                                snapshotRow(
                                    title: "Outstanding",
                                    value: outstandingRevenue.currency,
                                    detail: "Open invoices waiting to be collected",
                                    accent: .sweeplyWarning
                                )
                            }
                            .tag(0)

                            // Slide 2 — Revenue
                            VStack(alignment: .leading, spacing: 14) {
                                Divider()
                                snapshotRow(
                                    title: "Earned This Month",
                                    value: monthlyEarned.currency,
                                    detail: "From completed jobs",
                                    accent: .sweeplyAccent
                                )
                                Divider()
                                snapshotRow(
                                    title: "Upcoming Pipeline",
                                    value: upcomingPipelineValue.currency,
                                    detail: "Scheduled job value",
                                    accent: .sweeplyNavy
                                )
                                Divider()
                                snapshotRow(
                                    title: "Collected All-Time",
                                    value: totalRevenue.currency,
                                    detail: "Paid invoices total",
                                    accent: .sweeplyAccent
                                )
                            }
                            .tag(1)

                            // Slide 3 — Clients
                            VStack(alignment: .leading, spacing: 14) {
                                Divider()
                                snapshotRow(
                                    title: "Active This Month",
                                    value: "\(activeClientsCount)",
                                    detail: "Unique clients with visits",
                                    accent: .sweeplyNavy
                                )
                                Divider()
                                snapshotRow(
                                    title: "Total Clients",
                                    value: "\(totalActiveClients)",
                                    detail: "In your client base",
                                    accent: .sweeplyAccent
                                )
                                Divider()
                                snapshotRow(
                                    title: "Recurring Jobs",
                                    value: "\(recurringJobsThisMonth)",
                                    detail: "Repeating bookings this month",
                                    accent: .sweeplyWarning
                                )
                            }
                            .tag(2)

                            // Slide 4 — Service Mix
                            VStack(alignment: .leading, spacing: 14) {
                                let topServices = Array(serviceMix.prefix(3))
                                if topServices.isEmpty {
                                    VStack(spacing: 10) {
                                        Image(systemName: "chart.bar.xaxis")
                                            .font(.system(size: 28))
                                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                                        Text("Schedule jobs to see\nservice breakdown")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    Divider()
                                    ForEach(Array(topServices.enumerated()), id: \.offset) { i, svc in
                                        snapshotRow(
                                            title: svc.label,
                                            value: "\(svc.count) job\(svc.count == 1 ? "" : "s")",
                                            detail: String(format: "%.0f%% of this month's bookings", svc.percentage * 100),
                                            accent: [Color.sweeplyAccent, Color.sweeplyNavy, Color.sweeplyWarning][i % 3]
                                        )
                                        if i < topServices.count - 1 { Divider() }
                                    }
                                }
                            }
                            .tag(3)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 220)

                        HStack(spacing: 8) {
                            Spacer()
                            ForEach(0..<4, id: \.self) { index in
                                Capsule()
                                    .fill(index == selectedSnapshotSlide ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.8))
                                    .frame(width: index == selectedSnapshotSlide ? 18 : 8, height: 8)
                                    .animation(.easeInOut(duration: 0.2), value: selectedSnapshotSlide)
                            }
                            Spacer()
                        }
                    }
                }

                // 3. Next Job
                SectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        CardHeader(title: "Next Up", subtitle: "Your nearest scheduled visit", action: nil)

                        if let nextJob {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(nextJob.clientName)
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyNavy)
                                    Spacer()
                                    StatusBadge(status: nextJob.status)
                                }

                                Text(nextJob.serviceType.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)

                                Label(nextJob.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)

                                Label(nextJob.address, systemImage: "mappin.and.ellipse")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                    .lineLimit(2)

                                HStack(spacing: 12) {
                                    overviewChip(title: "Value", value: nextJob.price.currency)
                                    overviewChip(title: "Duration", value: durationLabel(for: nextJob.duration))
                                }
                            }
                        } else {
                            overviewEmptyState(
                                icon: "calendar.badge.checkmark",
                                title: "No upcoming jobs",
                                message: "When new visits are scheduled, the next one will appear here."
                            )
                        }
                    }
                }

                // 4. Service Distribution
                SectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        CardHeader(title: "Service Distribution", subtitle: "Most requested services this month", action: nil)

                        if serviceMix.isEmpty {
                            overviewEmptyState(
                                icon: "chart.bar.xaxis",
                                title: "No service mix yet",
                                message: "Once jobs are scheduled this month, the service split will show here."
                            )
                        } else {
                            VStack(spacing: 14) {
                                ForEach(serviceMix, id: \.label) { service in
                                    ServiceMixRow(label: service.label, percentage: service.percentage, count: service.count)
                                }
                            }
                        }
                    }
                }

                // 5. Top Clients
                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Top Clients", subtitle: "Highest activity this month", action: nil)

                        if topClients.isEmpty {
                            overviewEmptyState(
                                icon: "person.3.sequence",
                                title: "No client activity yet",
                                message: "Client rankings will update as jobs are completed."
                            )
                        } else {
                            Divider()
                            ForEach(Array(topClients.prefix(3).enumerated()), id: \.offset) { index, client in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(client.name)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("\(client.jobs) visits this month")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                    }

                                    Spacer()

                                    Text(client.revenue.currency)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyNavy)
                                }
                                .padding(.vertical, 4)

                                if index < min(topClients.count, 3) - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                serviceCatalogPreviewSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .refreshable {
            async let j: () = jobsStore.load(isAuthenticated: session.isAuthenticated)
            async let i: () = invoicesStore.load(isAuthenticated: session.isAuthenticated)
            async let c: () = clientsStore.load(isAuthenticated: session.isAuthenticated)
            _ = await (j, i, c)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .sheet(isPresented: $showServiceCatalog) {
            ServiceCatalogView()
        }
        .sheet(isPresented: $showAIChat) {
            AIChatView(
                onNewJob: nil,
                onNewClient: nil,
                onNewInvoice: nil
            )
            .environment(jobsStore)
            .environment(clientsStore)
            .environment(invoicesStore)
            .environment(profileStore)
        }
    }

    private var aiPreviewSection: some View {
        SectionCard {
            VStack(spacing: 0) {
                // Minimal header — title only, no badge/subtitle clutter
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.sweeplyNavy).frame(width: 40, height: 40)
                        Text("S")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text("Sweeply AI")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Spacer()
                    // Pagination dots
                    if !rotatingInsights.isEmpty {
                        HStack(spacing: 4) {
                            let count = min(rotatingInsights.count, 6)
                            let activeIdx = insightIndex % rotatingInsights.count
                            ForEach(0..<count, id: \.self) { i in
                                Circle()
                                    .fill(i == activeIdx ? Color.sweeplyNavy : Color.sweeplyBorder)
                                    .frame(width: i == activeIdx ? 6 : 4, height: i == activeIdx ? 6 : 4)
                                    .animation(.easeInOut(duration: 0.25), value: insightIndex)
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 14)

                // Rotating insight
                Group {
                    if rotatingInsights.isEmpty {
                        AIInsightRow(icon: "sparkles", text: "Book jobs and create invoices to unlock personalized AI insights.")
                    } else {
                        let idx = insightIndex % rotatingInsights.count
                        let insight = rotatingInsights[idx]
                        AIInsightRow(icon: insight.icon, text: insight.text, isWarning: insight.isWarning, isSuccess: insight.isSuccess)
                            .id(insightIndex)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: insightIndex)

                Divider().padding(.vertical, 14)

                // CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAIChat = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                        Text("Open AI Assistant").font(.system(size: 14, weight: .bold))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            guard !rotatingInsights.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                insightIndex = (insightIndex + 1) % rotatingInsights.count
            }
        }
    }

    private func snapshotRow(title: String, value: String, detail: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
    }

    private func overviewChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func overviewEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.45))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var serviceCatalogPreviewSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Service Catalog")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showServiceCatalog = true
                    } label: {
                        Text("View All")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.sweeplyAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                if catalogServices.isEmpty {
                    overviewEmptyState(
                        icon: "list.bullet.clipboard",
                        title: "No services configured",
                        message: "Add services to speed up job and invoice creation."
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(catalogServices.prefix(3)) { service in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.sweeplyAccent)
                                    .frame(width: 6, height: 6)
                                Text(service.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)
                                    .lineLimit(1)
                                Spacer()
                                Text(service.price.currency)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    if catalogServices.count > 3 {
                        Button {
                            showServiceCatalog = true
                        } label: {
                            let extra = catalogServices.count - 3
                            Text("+ \(extra) more service\(extra == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyAccent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func durationLabel(for duration: Double) -> String {
        if duration == floor(duration) {
            return "\(Int(duration))h"
        }
        return String(format: "%.1fh", duration)
    }
}

// MARK: - Subviews

private struct AIInsight {
    let icon: String
    let text: String
    var isWarning: Bool = false
    var isSuccess: Bool = false
}

private struct KPIBlock: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(width: 140, alignment: .leading)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

private struct AIInsightRow: View {
    let icon: String
    let text: String
    var isWarning: Bool = false
    var isSuccess: Bool = false

    var iconColor: Color {
        if isWarning { return Color.sweeplyDestructive }
        if isSuccess { return Color(red: 0.2, green: 0.7, blue: 0.4) }
        return Color.sweeplyAccent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(isWarning ? Color.sweeplyDestructive : Color.sweeplyNavy.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ServiceMixRow: View {
    let label: String
    let percentage: Double
    let count: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(count) jobs").font(.system(size: 11)).foregroundStyle(Color.sweeplyTextSub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sweeplyBorder.opacity(0.5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sweeplyNavy.opacity(0.8))
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    BusinessView()
        .environment(AppSession())
        .environment(ProfileStore())
}
