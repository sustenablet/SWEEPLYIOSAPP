import SwiftUI
import Charts

struct CleanerFinanceView: View {
    @Environment(JobsStore.self) private var jobsStore
    @Environment(TeamStore.self) private var teamStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self) private var session

    let membership: TeamMembership

    @AppStorage("cleanerFinancePeriod") private var selectedPeriodRaw: String = "This Month"
    @State private var appeared = false
    @State private var payments: [TeamMemberPayment] = []
    @State private var isLoadingPayments = false
    @State private var selectedJobId: UUID? = nil
    @State private var showJobDetail = false
    @State private var showAllCompleted = false
    @State private var showAllUpcoming = false

    private var selectedPeriod: Period { Period(rawValue: selectedPeriodRaw) ?? .month }

    enum Period: String, CaseIterable {
        case week  = "This Week"
        case month = "This Month"
        case all   = "All Time"
        
        var label: String {
            switch self {
            case .week: return "This Week".translated()
            case .month: return "This Month".translated()
            case .all: return "All Time".translated()
            }
        }
    }

    // MARK: - Derived

    private var allMyJobs: [Job] {
        jobsStore.jobs.filter { $0.assignedMemberId == membership.id }
    }

    private var periodStart: Date? {
        let cal = Calendar.current
        switch selectedPeriod {
        case .week:  return cal.dateInterval(of: .weekOfYear, for: Date())?.start
        case .month: return cal.dateInterval(of: .month, for: Date())?.start
        case .all:   return nil
        }
    }

    private var previousPeriodStart: Date? {
        let cal = Calendar.current
        switch selectedPeriod {
        case .week:  return cal.date(byAdding: .weekOfYear, value: -1, to: periodStart ?? Date())
        case .month: return cal.date(byAdding: .month, value: -1, to: periodStart ?? Date())
        case .all:   return nil
        }
    }

    private var completedJobs: [Job] {
        allMyJobs
            .filter { $0.status == .completed && (periodStart == nil || $0.date >= periodStart!) }
            .sorted { $0.date > $1.date }
    }

    private var previousPeriodEarnings: Double {
        guard let prevStart = previousPeriodStart, let currStart = periodStart else { return 0 }
        return allMyJobs
            .filter { $0.status == .completed && $0.date >= prevStart && $0.date < currStart }
            .reduce(0) { $0 + $1.price }
    }

    private var periodChange: Double {
        guard previousPeriodEarnings > 0, totalEarned > 0 else { return 0 }
        return ((totalEarned - previousPeriodEarnings) / previousPeriodEarnings) * 100
    }

    private var upcomingEarningsJobs: [Job] {
        allMyJobs
            .filter { $0.status == .scheduled || $0.status == .inProgress }
            .sorted { $0.date < $1.date }
    }

    private var totalEarned: Double { completedJobs.reduce(0) { $0 + $1.price } }
    private var avgPerJob: Double    { completedJobs.isEmpty ? 0 : totalEarned / Double(completedJobs.count) }
    private var scheduledTotal: Double { upcomingEarningsJobs.reduce(0) { $0 + $1.price } }

    private var payRateDisplay: String {
        guard membership.payRateEnabled && membership.payRateAmount > 0 else {
            return "Rate not set"
        }
        return "\(Int(membership.payRateAmount))/\(membership.payRateType == .perDay ? "day" : membership.payRateType == .perJob ? "job" : "week")"
    }

    private var weeklyEarningsData: [(week: Date, amount: Double)] {
        let cal = Calendar.current; let today = Date()
        return (0..<8).reversed().compactMap { ago -> (Date, Double)? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -ago, to: cal.startOfDay(for: today)),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
            let total = allMyJobs
                .filter { $0.status == .completed && $0.date >= start && $0.date < end }
                .reduce(0.0) { $0 + $1.price }
            return (start, total)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    Divider()

                    heroStrip
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 8)

                    // Pay Rate Banner
                    payRateBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    VStack(spacing: 12) {
                        completedSection
                        if !upcomingEarningsJobs.isEmpty { scheduledSection }
                        if !payments.isEmpty { paymentsSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .task {
                await loadPayments()
            }
            .sheet(isPresented: $showJobDetail) {
                if let jobId = selectedJobId {
                    NavigationStack {
                        JobDetailView(jobId: jobId)
                    }
                    .environment(jobsStore)
                    .environment(clientsStore)
                }
            }
            .sheet(isPresented: $showAllCompleted) {
                NavigationStack {
                    CompletedJobsListView(jobs: completedJobs, membership: membership)
                        .environment(jobsStore)
                        .environment(clientsStore)
                }
            }
            .sheet(isPresented: $showAllUpcoming) {
                NavigationStack {
                    UpcomingJobsListView(jobs: upcomingEarningsJobs, membership: membership)
                        .environment(jobsStore)
                        .environment(clientsStore)
                }
            }
        }
    }

    // MARK: - Load Payments

    private func loadPayments() async {
        guard let ownerId = session.userId else { return }
        isLoadingPayments = true
        payments = await teamStore.loadPayments(memberId: membership.id, ownerId: ownerId)
        isLoadingPayments = false
    }

    // MARK: - Header

    private var headerRow: some View {
        PageHeader(eyebrow: "EARNINGS", title: "Finance", subtitle: selectedPeriod.rawValue) {
            periodPicker
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases, id: \.self) { period in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(duration: 0.2)) { selectedPeriodRaw = period.rawValue }
                } label: {
                    Text(period == .week ? "Wk" : period == .month ? "Mo" : "All")
                        .font(.system(size: 12, weight: selectedPeriod == period ? .bold : .medium))
                        .foregroundStyle(selectedPeriod == period ? .white : Color.sweeplyTextSub)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedPeriod == period ? Color.sweeplyNavy : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sweeplySurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Hero Strip

    private var heroStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
statCell(value: totalEarned.currency, label: "Gross Earned".translated(), change: periodChange)
                statCell(value: "\(completedJobs.count)", label: "Jobs Done".translated())
                statCell(value: avgPerJob > 0 ? avgPerJob.currency : "—", label: "Avg / Job".translated())
            }
            .padding(.vertical, 14)

            if !weeklyEarningsData.isEmpty {
                Chart(weeklyEarningsData, id: \.week) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        y: .value("Earned", point.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sweeplyAccent.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Earned", point.amount)
                    )
                    .foregroundStyle(Color.sweeplyAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 32)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Pay Rate Banner

    private var payRateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.sweeplyAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your Pay Rate".translated())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(membership.payRateEnabled ? payRateDisplay : "Contact manager to set up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(membership.payRateEnabled ? Color.sweeplyNavy : Color.sweeplyTextSub)
            }

            Spacer()
        }
        .padding(14)
        .background(membership.payRateEnabled ? Color.sweeplyAccent.opacity(0.08) : Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statCell(value: String, label: String, change: Double = 0) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .textCase(.uppercase)
                    .tracking(0.3)
                if change != 0 && label == "Gross Earned" {
                    Text(change >= 0 ? "+\(Int(change))%" : "\(Int(change))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(change >= 0 ? Color.sweeplySuccess : .red)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle().fill(Color.sweeplyBorder).frame(width: 1, height: 40)
    }

    // MARK: - Completed Jobs Section

    private var completedSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(
                    title: "Completed Jobs".translated(),
                    subtitle: selectedPeriod.rawValue,
                    badge: completedJobs.isEmpty ? nil : "\(completedJobs.count)",
                    action: completedJobs.isEmpty ? nil : { showAllCompleted = true }
                )

                if jobsStore.isLoading {
                    skeletonRows
                } else if completedJobs.isEmpty {
                    emptyCompletedState
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(completedJobs.enumerated()), id: \.element.id) { index, job in
                            financeJobRow(job: job)
                            if index < completedJobs.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }

                    Divider().padding(.top, 8)

                    HStack {
                        Text("Total".translated())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(totalEarned.currency)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var emptyCompletedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyAccent.opacity(0.4))
            Text(selectedPeriod == .all ? "No completed jobs yet".translated() : "No completed jobs this period".translated())
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Scheduled Earnings Section

    private var scheduledSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(
                    title: "Upcoming Earnings".translated(),
                    subtitle: "Scheduled jobs".translated(),
                    badge: upcomingEarningsJobs.isEmpty ? nil : "\(upcomingEarningsJobs.count)",
                    action: upcomingEarningsJobs.isEmpty ? nil : { showAllUpcoming = true }
                )

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(upcomingEarningsJobs.prefix(5).enumerated()), id: \.element.id) { index, job in
                        financeJobRow(job: job)
                        if index < min(upcomingEarningsJobs.count, 5) - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }

                if scheduledTotal > 0 {
                    Divider().padding(.top, 8)
                    HStack {
                        Text("Potential".translated())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(scheduledTotal.currency)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Payments Section

    private var paymentsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Payment History".translated(), subtitle: "Received payments".translated(), action: nil)

                if isLoadingPayments {
                    skeletonRows
                } else if payments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "banknote")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sweeplyAccent.opacity(0.4))
                        Text("No payments received yet".translated())
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                            paymentRow(payment: payment)
                            if index < payments.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func paymentRow(payment: TeamMemberPayment) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(payment.paidAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
.foregroundStyle(Color.sweeplySuccess)
                Rectangle()
                    .fill(Color.sweeplySuccess.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 52)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(payment.notes.isEmpty ? "Payment received" : payment.notes)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Paid \(payment.paidAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.vertical, 10)

            Spacer()

            Text(payment.amount.currency)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplySuccess)
        }
    }

    // MARK: - Job Row

    private func financeJobRow(job: Job) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedJobId = job.id
            showJobDetail = true
        } label: {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(job.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(job.status == .completed ? Color.sweeplySuccess : Color.sweeplyAccent)
                    Rectangle()
                        .fill((job.status == .completed ? Color.sweeplySuccess : Color.sweeplyAccent).opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 52)
                .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.clientName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(job.serviceType.rawValue.translated())
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.vertical, 10)

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(job.price.currency)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(job.status == .completed ? Color.sweeplyNavy : Color.sweeplyAccent)
                    statusPill(job.status)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ status: JobStatus) -> some View {
        let color: Color = status == .completed ? Color.sweeplySuccess : status == .inProgress ? .orange : Color.sweeplyAccent
        return Text(status.rawValue.translated())
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var skeletonRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.sweeplyBorder.opacity(0.4))
                    .frame(height: 52)
            }
        }
    }
}

// MARK: - Completed Jobs List View

struct CompletedJobsListView: View {
    let jobs: [Job]
    let membership: TeamMembership
    
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedJobId: UUID?
    @State private var showJobDetail = false
    @State private var searchText = ""
    @State private var refreshTrigger = false
    @State private var groupByPeriod: GroupByPeriod = .day
    
    private enum GroupByPeriod: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
    }
    
    private var filteredJobs: [Job] {
        if searchText.isEmpty { return jobs }
        let query = searchText.lowercased()
        return jobs.filter { job in
            let client = clientsStore.clients.first { $0.id == job.clientId }
            let clientName = client?.name.lowercased() ?? ""
            let clientAddress = client?.address.lowercased() ?? ""
            let serviceName = job.serviceType.rawValue.lowercased()
            return clientName.contains(query) || clientAddress.contains(query) || serviceName.contains(query)
        }
    }
    
    private var totalEarnings: Double {
        jobs.reduce(0) { $0 + $1.price }
    }
    
    private var groupedJobs: [(date: Date, jobs: [Job])] {
        let filtered = filteredJobs
        switch groupByPeriod {
        case .day:
            let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            return grouped
                .map { (date: $0.key, jobs: $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.date > $1.date }
        case .week:
            let grouped = Dictionary(grouping: filtered) { job in
                let cal = Calendar.current
                let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: job.date)
                return cal.date(from: components) ?? job.date
            }
            return grouped
                .map { (date: $0.key, jobs: $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.date > $1.date }
        case .month:
            let grouped = Dictionary(grouping: filtered) { job in
                let cal = Calendar.current
                let components = cal.dateComponents([.year, .month], from: job.date)
                return cal.date(from: components) ?? job.date
            }
            return grouped
                .map { (date: $0.key, jobs: $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.date > $1.date }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                filterBar
                statsSummary
                if filteredJobs.isEmpty {
                    emptyState
                } else {
                    jobsListSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done".translated()) { dismiss() }
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .sheet(isPresented: $showJobDetail) {
            if let jobId = selectedJobId {
                NavigationStack {
                    JobDetailView(jobId: jobId)
                }
                .environment(jobsStore)
                .environment(clientsStore)
            }
        }
    }
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                TextField("Search clients or services...", text: $searchText)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
            }
            .padding(12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
            
            HStack(spacing: 6) {
                ForEach(GroupByPeriod.allCases, id: \.self) { period in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { groupByPeriod = period }
                    } label: {
                        Text(period.rawValue)
                            .font(.system(size: 12, weight: groupByPeriod == period ? .bold : .medium))
                            .foregroundStyle(groupByPeriod == period ? .white : Color.sweeplyTextSub)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(groupByPeriod == period ? Color.sweeplyNavy : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.sweeplyAccent.opacity(0.4))
            Text(searchText.isEmpty ? "No completed jobs yet".translated() : "No jobs match your search".translated())
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            if !searchText.isEmpty {
                Button("Clear Search".translated()) {
                    searchText = ""
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Completed Jobs".translated())
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text(totalEarnings.currency)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .frame(minHeight: 76, alignment: .center)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var statsSummary: some View {
        HStack(spacing: 16) {
            statBox(title: "Jobs", value: "\(jobs.count)", icon: "briefcase.fill", color: Color.sweeplyNavy)
            statBox(title: "Avg/Job", value: (jobs.isEmpty ? 0 : totalEarnings / Double(jobs.count)).currency, icon: "chart.bar.fill", color: Color.sweeplyAccent)
        }
        .padding(.vertical, 4)
    }
    
    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
    
    private var jobsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(groupedJobs.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(dateHeaderFormatter.string(from: group.date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .padding(.horizontal, 4)
                    
                    VStack(spacing: 0) {
                        ForEach(Array(group.jobs.enumerated()), id: \.element.id) { index, job in
                            completedJobRow(job: job, client: clientsStore.clients.first { $0.id == job.clientId })
                            if index < group.jobs.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }
    
    private func completedJobRow(job: Job, client: Client?) -> some View {
        HStack(spacing: 12) {
            financeAvatarCircle(client?.initials ?? "?")
            
            VStack(alignment: .leading, spacing: 4) {
                Text(client?.name ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                
                HStack(spacing: 4) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                    if let city = client?.city, !city.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text(city)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(shortDateFormatter.string(from: job.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    Text("at".translated())
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text(financeTimeString(from: job.date))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                }
            }
            
            Spacer()
            
            Text(job.price.currency)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
    
    private var shortDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }
    
    private var dateHeaderFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }
}

// MARK: - Upcoming Jobs List View

struct UpcomingJobsListView: View {
    let jobs: [Job]
    let membership: TeamMembership
    
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(\.dismiss) private var dismiss
    
    private var totalPotential: Double {
        jobs.reduce(0) { $0 + $1.price }
    }
    
    private var scheduledCount: Int {
        jobs.filter { $0.status == .scheduled }.count
    }
    
    private var inProgressCount: Int {
        jobs.filter { $0.status == .inProgress }.count
    }
    
    private var groupedJobs: [(date: Date, jobs: [Job])] {
        let grouped = Dictionary(grouping: jobs) { Calendar.current.startOfDay(for: $0.date) }
        return grouped
            .map { (date: $0.key, jobs: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                statsSummary
                jobsListSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done".translated()) { dismiss() }
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Upcoming Earnings".translated())
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text(totalPotential.currency)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyAccent)
        }
        .frame(minHeight: 76, alignment: .center)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var statsSummary: some View {
        HStack(spacing: 16) {
            statBox(title: "Jobs", value: "\(jobs.count)", icon: "calendar.badge.clock", color: Color.sweeplyNavy)
            statBox(title: "Scheduled", value: "\(scheduledCount)", icon: "clock.fill", color: Color.sweeplyAccent)
            statBox(title: "In Progress", value: "\(inProgressCount)", icon: "play.circle.fill", color: .orange)
        }
        .padding(.vertical, 4)
    }
    
    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
    
    private var jobsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(groupedJobs.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(dateHeaderFormatter.string(from: group.date))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(group.jobs.reduce(0) { $0 + $1.price }.currency)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .padding(.horizontal, 4)
                    
                    VStack(spacing: 0) {
                        ForEach(Array(group.jobs.enumerated()), id: \.element.id) { index, job in
                            upcomingJobRow(job: job, client: clientsStore.clients.first { $0.id == job.clientId })
                            if index < group.jobs.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }
    
    private func upcomingJobRow(job: Job, client: Client?) -> some View {
        HStack(spacing: 12) {
            financeAvatarCircle(client?.initials ?? "?")
            
            VStack(alignment: .leading, spacing: 4) {
                Text(client?.name ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                
                HStack(spacing: 4) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                    if let city = client?.city, !city.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text(city)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(shortDateFormatter.string(from: job.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    Text("at".translated())
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text(financeTimeString(from: job.date))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                Text(job.price.currency)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyAccent)
                statusPill(job.status)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
    
    private func statusPill(_ status: JobStatus) -> some View {
        Text(status.rawValue.translated())
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.1))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }
    
    private var shortDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }
    
    private var dateHeaderFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }
}
    
    private var shortDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }
    
    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .scheduled: return Color.sweeplyAccent
        case .inProgress: return .orange
        case .completed: return Color.sweeplySuccess
        case .cancelled: return .red
        }
    }

    // MARK: - Helper Functions

fileprivate func financeAvatarCircle(_ initials: String) -> some View {
    ZStack {
        Circle()
            .fill(Color.sweeplyAccent.gradient)
            .frame(width: 44, height: 44)
        Text(initials)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
    }
}

fileprivate func financeTimeString(from date: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: date)
}