import SwiftUI

struct DashboardView: View {
    @State private var jobs: [Job] = MockData.makeJobs()
    @State private var invoices: [Invoice] = MockData.makeInvoices()

    private let profile = MockData.profile
    private let pagePadding: CGFloat = 20

    @State private var appeared = false

    // Mock: pretend user is new.
    @State private var showPlaybook: Bool = true
    @State private var playbookDone: [Bool] = Array(repeating: false, count: 4)

    @State private var showProfileDialog = false

    private var unreadNotificationCount: Int { 1 }

    private var firstName: String {
        profile.fullName.split(separator: " ").first.map(String.init) ?? profile.fullName
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 0..<12: salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        default: salutation = "Good evening"
        }
        return "\(salutation), \(firstName)"
    }

    private var todaysDateFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var initials: String {
        profile.fullName
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
    }

    private var todayJobs: [Job] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return jobs
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    private var totalClients: Int { MockData.clients.count }

    private var upcomingJobsCount: Int {
        jobs.filter { $0.status == .scheduled }.count
    }

    private var revenueTotal: Double {
        invoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
    }

    private var outstandingTotal: Double {
        invoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.amount }
    }

    private var allPlaybookDone: Bool {
        playbookDone.allSatisfy { $0 }
    }

    private var completedCountAllTime: Int {
        jobs.filter { $0.status == .completed }.count
    }

    private var thisWeekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), end: Date().addingTimeInterval(86400 * 7))
    }

    private var jobsThisWeek: [Job] {
        jobs.filter { $0.date >= thisWeekInterval.start && $0.date < thisWeekInterval.end }
    }

    private var thisWeekJobsCount: Int {
        jobsThisWeek.filter { $0.status != .cancelled }.count
    }

    private var remainingTodayCount: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return jobs.filter { $0.date >= start && $0.date < end && ($0.status == .scheduled || $0.status == .inProgress) }.count
    }

    private var weekEarned: Double {
        jobsThisWeek
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.price }
    }

    private var weekEarnedCurrency: String { weekEarned.currency }

    private var businessHealthWeekRange: String {
        let start = thisWeekInterval.start
        let end = thisWeekInterval.end.addingTimeInterval(-1) // inclusive-ish end for display
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private var visitsScheduledThisWeekCount: Int {
        jobsThisWeek.filter { $0.status == .scheduled }.count
    }

    private var outstandingInvoicesSorted: [Invoice] {
        invoices
            .filter { $0.status != .paid }
            .sorted { a, b in
                let rankA = a.status == .overdue ? 0 : 1
                let rankB = b.status == .overdue ? 0 : 1
                if rankA != rankB { return rankA < rankB }
                return a.dueDate < b.dueDate
            }
    }

    private var outstandingInvoicesTop: [Invoice] {
        Array(outstandingInvoicesSorted.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                quickStatsRow
                if showPlaybook && !allPlaybookDone {
                    playbookSection
                }
                statsGrid
                todaysScheduleCard
                businessHealthCard
                outstandingInvoicesCard
            }
            .padding(.horizontal, pagePadding)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .confirmationDialog(
            "",
            isPresented: $showProfileDialog,
            titleVisibility: .hidden
        ) {
            Button("Settings") { showProfileDialog = false }
            Button("Sign Out", role: .destructive) { showProfileDialog = false }
        } message: {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.fullName).font(.system(size: 14, weight: .semibold))
                Text(profile.businessName).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
            }
        }
    }

    // MARK: - Section 1: Header
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(Font.custom("BricolageGrotesque-Bold", size: 22))
                    .foregroundStyle(Color.sweeplyAccent)
                Text(todaysDateFormatted)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.sweeplyAccent)

                    if unreadNotificationCount > 0 {
                        Circle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: 8, height: 8)
                            .offset(x: -2, y: -2)
                    }
                }

                Button { showProfileDialog = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            .frame(width: 38, height: 38)
                        Text(initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Section 2: Mobile Quick Stats Row
    private var quickStatsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                QuickStatCard(
                    value: "\(totalClients)",
                    label: "Total Clients",
                    icon: "person.2.fill",
                    accent: .sweeplyAccent
                )

                QuickStatCard(
                    value: "\(upcomingJobsCount)",
                    label: "Upcoming Jobs",
                    icon: "calendar",
                    accent: .sweeplyAccent
                )

                QuickStatCard(
                    value: revenueTotal.currency,
                    label: "Revenue",
                    icon: "dollarsign.circle.fill",
                    accent: .sweeplySuccess
                )

                QuickStatCard(
                    value: outstandingTotal.currency,
                    label: "Outstanding",
                    icon: "exclamationmark.triangle.fill",
                    accent: .sweeplyWarning
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20) // bleed trick
    }

    // MARK: - Section 3: Getting Started Checklist
    private var playbookSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text("Get started")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.25)) { showPlaybook = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .padding(6)
                    }
                    .accessibilityLabel("Dismiss")
                }

                VStack(spacing: 10) {
                    playbookStepRow(index: 0, title: "Add your first client", systemIcon: "person.badge.plus")
                    playbookStepRow(index: 1, title: "Schedule your first job", systemIcon: "calendar.badge.plus")
                    playbookStepRow(index: 2, title: "Create your first invoice", systemIcon: "doc.badge.plus")
                    playbookStepRow(index: 3, title: "Set up your business profile", systemIcon: "building.2")
                }

                Text("\(playbookDoneCount) of 4 complete")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
    }

    private var playbookDoneCount: Int { playbookDone.filter { $0 }.count }

    @ViewBuilder
    private func playbookStepRow(index: Int, title: String, systemIcon: String) -> some View {
        let done = playbookDone[index]
        Button {
            withAnimation(.spring(duration: 0.25)) {
                playbookDone[index].toggle()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(done ? Color.sweeplySuccess : .clear)
                        .overlay(
                            Circle()
                                .stroke(done ? Color.sweeplySuccess : Color.sweeplyBorder.opacity(0.9), lineWidth: 1)
                        )
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(done ? Color.sweeplyTextSub : Color.primary)
                    .strikethrough(done, color: Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 4: Mobile Stats Grid (2×2)
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MobileStatTile(label: "This Week", value: "\(thisWeekJobsCount) jobs", isMonospaced: false)
            MobileStatTile(label: "Completed", value: "\(completedCountAllTime)", isMonospaced: false)
            MobileStatTile(label: "Remaining", value: "\(remainingTodayCount)", isMonospaced: false)
            MobileStatTile(label: "Week Earned", value: weekEarnedCurrency, isMonospaced: true)
        }
    }

    // MARK: - Section 5: Today's Schedule Card
    private var todaysScheduleCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Today's Schedule", action: {})

                if todayJobs.isEmpty {
                    emptyState(
                        icon: "calendar.badge.exclamationmark",
                        text: "No jobs scheduled for today"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(todayJobs.enumerated()), id: \.element.id) { idx, job in
                            JobRow(job: job)
                            if idx < todayJobs.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 6: Business Health Card
    private var businessHealthCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Business Health")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(businessHealthWeekRange)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Button(action: {}) {
                            HStack(spacing: 3) {
                                Text("View all")
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    iconSquare(
                        background: Color.sweeplySuccess.opacity(0.12),
                        systemIcon: "dollarsign",
                        systemIconColor: Color.sweeplySuccess
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Job Value")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Total value of this week's jobs")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(weekEarnedCurrency)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                        TrendBadge(value: "+18%", isPositive: true)
                    }
                }
                .padding(.vertical, 8)

                Divider()

                HStack(spacing: 12) {
                    iconSquare(
                        background: Color.sweeplyNavy.opacity(0.08),
                        systemIcon: "calendar",
                        systemIconColor: Color.sweeplyNavy
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Visits Scheduled")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Visits scheduled this week")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(visitsScheduledThisWeekCount)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                        TrendBadge(value: "+8%", isPositive: true)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Section 7: Outstanding Invoices Card
    private var outstandingInvoicesCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Outstanding Invoices", action: {})

                if outstandingInvoicesTop.isEmpty {
                    emptyState(
                        icon: "checkmark.seal.fill",
                        text: "All caught up — no outstanding invoices"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(outstandingInvoicesTop.enumerated()), id: \.element.id) { idx, invoice in
                            InvoiceRow(invoice: invoice)
                            if idx < outstandingInvoicesTop.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mutations
    private func updateJobStatus(_ jobID: UUID, to status: JobStatus) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].status = status
    }

    private func updateInvoiceStatus(_ invoiceID: UUID, to status: InvoiceStatus) {
        guard let idx = invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
        invoices[idx].status = status
    }

    // MARK: - Small building blocks
    private func durationString(_ hours: Double) -> String {
        if hours == 1 { return "1h" }
        if hours == floor(hours) { return "\(Int(hours))h" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func statusDotColor(for status: JobStatus) -> Color {
        switch status {
        case .completed:   return Color.sweeplySuccess
        case .inProgress:  return Color(red: 0.4, green: 0.45, blue: 0.95)
        case .scheduled:   return Color.sweeplyTextSub.opacity(0.5)
        case .cancelled:   return Color.sweeplyDestructive
        }
    }

    private func iconSquare(background: Color, systemIcon: String, systemIconColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(background)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: systemIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(systemIconColor)
            )
    }

    private func weekRangeString() -> String { businessHealthWeekRange }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Nested view components
    private struct SectionCard<Content: View>: View {
        let content: Content
        init(@ViewBuilder _ content: () -> Content) { self.content = content() }
        var body: some View {
            content
                .padding(16)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
        }
    }

    private struct CardHeader: View {
        let title: String
        var action: (() -> Void)? = nil

        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                if let action {
                    Button(action: action) {
                        HStack(spacing: 3) {
                            Text("View all")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
            }
        }
    }

    private struct QuickStatCard: View {
        let value: String
        let label: String
        let icon: String
        let accent: Color

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.5)
            }
            .frame(width: 140, height: 90, alignment: .topLeading)
            .padding(14)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
        }
    }

    private struct MobileStatTile: View {
        let label: String
        let value: String
        let isMonospaced: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: isMonospaced ? .monospaced : .default))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .padding(16)
            .background(Color.sweeplyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private struct TrendBadge: View {
        let value: String
        let isPositive: Bool

        var body: some View {
            HStack(spacing: 2) {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(value)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isPositive ? Color.sweeplySuccess : Color.sweeplyDestructive)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((isPositive ? Color.sweeplySuccess : Color.sweeplyDestructive).opacity(0.1))
            .clipShape(Capsule())
        }
    }

    private struct JobRow: View {
        let job: Job
        @State private var isMenuPresented = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(timeString)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text(amPm)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .frame(width: 36, alignment: .trailing)

                    Circle()
                        .fill(statusDotColor(for: job.status))
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(job.clientName)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Spacer()

                            Text(job.price.currency)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }

                        HStack(spacing: 0) {
                            Text("\(job.serviceType.rawValue) · \(durationString(job.duration)) · \(job.address)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .lineLimit(1)

                            Spacer()

                            Menu {
                                Button {
                                    // Delegated to parent via environment? Mock: no-op here.
                                } label: {
                                    Label("Start Job", systemImage: "play.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .menuOrder(.fixed)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        }

        private var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "h:mm"
            return f.string(from: job.date)
        }

        private var amPm: String {
            let f = DateFormatter()
            f.dateFormat = "a"
            return f.string(from: job.date).uppercased()
        }
    }

    private struct InvoiceRow: View {
        let invoice: Invoice
        @Binding var invoices: [Invoice]

        var body: some View {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(invoice.clientName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()

                HStack(spacing: 8) {
                    Text(invoice.amount.currency)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    InvoiceStatusBadge(status: invoice.status)
                    Button("Mark Paid") {
                        if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
                            invoices[idx].status = .paid
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.sweeplyNavy)
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 10)
        }
    }

    private struct InvoiceStatusBadge: View {
        let status: InvoiceStatus

        var body: some View {
            let color = statusColor
            Text(status.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.10))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.20), lineWidth: 1)
                )
        }

        private var statusColor: Color {
            switch status {
            case .paid:    return Color.sweeplySuccess
            case .unpaid:  return Color.sweeplyWarning
            case .overdue: return Color.sweeplyDestructive
            }
        }
    }

}

// MARK: - KPI Card
struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let trend: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                Spacer()
                if let trend {
                    Text(trend)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplySuccess)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.sweeplySuccess.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.primary)
                .tracking(-0.5)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.2)
        }
        .padding(Spacing.base)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Job Row
struct JobRowView: View {
    let job: Job

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Time column
            VStack(alignment: .center, spacing: 2) {
                Text(timeString)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                Text(amPm)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(width: 38)

            // Divider dot
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            // Job info
            VStack(alignment: .leading, spacing: 3) {
                Text(job.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            // Status + price
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: job.status)
                Text(job.price.currency)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .padding(Spacing.md)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 1)
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: job.date)
    }
    private var amPm: String {
        let f = DateFormatter(); f.dateFormat = "a"
        return f.string(from: job.date).uppercased()
    }
    private var statusColor: Color {
        switch job.status {
        case .scheduled:  return Color.sweeplyAccent
        case .inProgress: return Color(red: 0.4, green: 0.45, blue: 0.95)
        case .completed:  return Color.sweeplySuccess
        case .cancelled:  return Color.sweeplyTextSub
        }
    }
}

// MARK: - Invoice Row
struct InvoiceRowView: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(invoice.invoiceNumber)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.amount.currency)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                InvoiceStatusBadge(status: invoice.status)
            }
        }
        .padding(Spacing.md)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 1)
    }
}

// MARK: - Status Badges
struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .scheduled:  return Color.sweeplyAccent
        case .inProgress: return Color(red: 0.4, green: 0.45, blue: 0.95)
        case .completed:  return Color.sweeplySuccess
        case .cancelled:  return Color.sweeplyTextSub
        }
    }
}

struct InvoiceStatusBadge: View {
    let status: InvoiceStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .paid:    return Color.sweeplySuccess
        case .unpaid:  return Color.sweeplyWarning
        case .overdue: return Color.sweeplyDestructive
        }
    }
}

// MARK: - Extensions
extension Double {
    var currency: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}

#Preview {
    DashboardView()
}
