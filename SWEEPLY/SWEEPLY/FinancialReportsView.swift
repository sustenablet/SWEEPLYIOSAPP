import SwiftUI
import Charts

struct FinancialReportsView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(InvoicesStore.self)       private var invoicesStore
    @Environment(ExpenseStore.self)        private var expenseStore
    @Environment(JobsStore.self)           private var jobsStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    // ── Persisted state ──
    @AppStorage("financesOverviewPeriod")  private var overviewPeriodRaw: String = OverviewPeriod.sixMonth.rawValue
    @AppStorage("cashflowForecastWeeks")   private var forecastWeekCount: Int = 8

    // ── Transient state ──
    @State private var selectedOverviewMonth: String? = nil
    @State private var selectedForecastWeekLabel: String? = nil
    @State private var selectedCashflowBar: String? = nil
    @State private var selectedCashflowValue: Double = 0
    @State private var plPeriod: PLPeriod = .thisMonth
    @State private var revenueSlide: Int = 0
    @State private var showForecastPopup: Bool = false
    @State private var popupWeek: ForecastWeek? = nil
    @State private var showOverviewPeriodFilter: Bool = false

    // MARK: - Enums

    enum OverviewPeriod: String, CaseIterable {
        case oneMonth   = "1M"
        case threeMonth = "3M"
        case sixMonth   = "6M"
        case twelveMonth = "12M"
    }

    enum PLPeriod: String, CaseIterable {
        case thisMonth = "Month"
        case lastMonth = "Last Mo."
        case ytd       = "Year"
    }

    private var plPeriodInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch plPeriod {
        case .thisMonth:
            return cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        case .lastMonth:
            guard let lastMonth = cal.date(byAdding: .month, value: -1, to: now),
                  let interval = cal.dateInterval(of: .month, for: lastMonth)
            else { return DateInterval(start: now, duration: 0) }
            return interval
        case .ytd:
            let startOfYear = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return DateInterval(start: startOfYear, end: now)
        }
    }

    private var plPriorInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch plPeriod {
        case .thisMonth:
            guard let priorStart = cal.date(byAdding: .month, value: -1, to: plPeriodInterval.start),
                  let interval = cal.dateInterval(of: .month, for: priorStart)
            else { return DateInterval(start: now, duration: 0) }
            return interval
        case .lastMonth:
            guard let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: now),
                  let interval = cal.dateInterval(of: .month, for: twoMonthsAgo)
            else { return DateInterval(start: now, duration: 0) }
            return interval
        case .ytd:
            let startOfYear = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            guard let priorYearStart = cal.date(byAdding: .year, value: -1, to: startOfYear),
                  let priorYearEndDate = cal.date(byAdding: .day, value: -1, to: startOfYear)
            else { return DateInterval(start: startOfYear, end: now) }
            return DateInterval(start: priorYearStart, end: priorYearEndDate)
        }
    }

    // MARK: - Intervals

    private var currentMonthInterval: DateInterval {
        plPeriodInterval
    }

    private var priorMonthInterval: DateInterval {
        plPriorInterval
    }

    private var ytdInterval: DateInterval {
        let cal = Calendar.current
        let jan1 = cal.date(from: cal.dateComponents([.year], from: Date())) ?? Date()
        return DateInterval(start: jan1, end: Date())
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var plInterval: DateInterval {
        switch plPeriod {
        case .thisMonth: return currentMonthInterval
        case .lastMonth: return priorMonthInterval
        case .ytd:       return ytdInterval
        }
    }

    // MARK: - Invoice data

    private var invoices: [Invoice] { invoicesStore.invoices }
    private var paidInvoices: [Invoice]   { invoices.filter { $0.status == .paid } }
    private var unpaidInvoices: [Invoice]  { invoices.filter { $0.status == .unpaid } }
    private var overdueInvoices: [Invoice] { invoices.filter { $0.status == .overdue } }
    private var paidTotal:    Double { paidInvoices.reduce(0)   { $0 + $1.total } }
    private var unpaidTotal:  Double { unpaidInvoices.reduce(0) { $0 + $1.total } }
    private var overdueTotal: Double { overdueInvoices.reduce(0){ $0 + $1.total } }
    private var collectionRate: Double {
        let t = paidTotal + unpaidTotal + overdueTotal
        guard t > 0 else { return 0 }
        return paidTotal / t
    }

    // MARK: - P&L data (period-driven)

    private var plIncome: Double {
        invoices.filter { $0.status == .paid && plInterval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }
    private var plExpenses: Double { expenseStore.total(in: plInterval) }
    private var plNet:      Double { plIncome - plExpenses }

    // MARK: - YTD data

    private var ytdRevenue: Double {
        invoices.filter { $0.status == .paid && ytdInterval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }
    private var ytdExpenses:      Double { expenseStore.total(in: ytdInterval) }
    private var ytdNet:           Double { ytdRevenue - ytdExpenses }
    private var ytdInvoiceCount:  Int {
        invoices.filter { $0.status == .paid && ytdInterval.contains($0.createdAt) }.count
    }

    // MARK: - Revenue Overview chart

    private var overviewPeriod: OverviewPeriod { OverviewPeriod(rawValue: overviewPeriodRaw) ?? .sixMonth }

    private var overviewBarData: [MonthlyBar] {
        let count: Int
        switch overviewPeriod {
        case .oneMonth:    count = 1
        case .threeMonth: count = 3
        case .sixMonth:   count = 6
        case .twelveMonth: count = 12
        }
        let cal = Calendar.current
        let now = Date()
        let f = DateFormatter(); f.dateFormat = "MMM"
        return (0..<count).reversed().compactMap { offset -> MonthlyBar? in
            guard let monthStart = cal.date(byAdding: .month, value: -offset, to: now),
                  let interval = cal.dateInterval(of: .month, for: monthStart) else { return nil }
            let collected   = invoices.filter { $0.status == .paid  && $0.createdAt >= interval.start && $0.createdAt < interval.end }.reduce(0) { $0 + $1.total }
            let outstanding = invoices.filter { $0.status != .paid  && $0.createdAt >= interval.start && $0.createdAt < interval.end }.reduce(0) { $0 + $1.total }
            return MonthlyBar(month: f.string(from: interval.start), collected: collected, scheduled: outstanding)
        }
    }

    private var overviewTrend: Double? {
        guard overviewBarData.count >= 2 else { return nil }
        let last = overviewBarData[overviewBarData.count - 1].collected
        let prev = overviewBarData[overviewBarData.count - 2].collected
        guard prev > 0 else { return nil }
        return (last - prev) / prev
    }

    // MARK: - Forecast data

    private var cashflowForecast: [ForecastWeek] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let upcomingJobs     = jobsStore.jobs.filter { $0.status == .scheduled && $0.date >= today }
        let unpaidInv        = invoicesStore.invoices.filter { $0.status == .unpaid && $0.dueDate >= today }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return (0..<forecastWeekCount).map { offset in
            let weekStart = cal.date(byAdding: .weekOfYear, value: offset, to: today) ?? today
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let interval  = DateInterval(start: weekStart, end: weekEnd)
            let wJobs     = upcomingJobs.filter { interval.contains($0.date) }
            let wInv      = unpaidInv.filter    { interval.contains($0.dueDate) }
            return ForecastWeek(
                weekStart: weekStart,
                weekLabel: fmt.string(from: weekStart),
                jobsAmount: wJobs.reduce(0) { $0 + $1.price },
                invoicesAmount: wInv.reduce(0) { $0 + $1.amount },
                jobCount: wJobs.count,
                invoiceCount: wInv.count
            )
        }
    }

    private var forecastTotal:     Double { cashflowForecast.reduce(0) { $0 + $1.total } }
    private var forecastAvgWeekly: Double { cashflowForecast.isEmpty ? 0 : forecastTotal / Double(cashflowForecast.count) }
    private var forecastMax:       Double { max(cashflowForecast.map { $0.total }.max() ?? 1, 1) }

    private var selectedForecastWeek: ForecastWeek? {
        guard let label = selectedForecastWeekLabel else { return nil }
        return cashflowForecast.first { $0.weekLabel == label }
    }

    // MARK: - Invoice aging (unpaid + overdue only)

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var agingNotDueYet: [Invoice] {
        (unpaidInvoices + overdueInvoices).filter { $0.dueDate > today }
    }
    private var aging1to7: [Invoice] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: today)!
        return (unpaidInvoices + overdueInvoices).filter { $0.dueDate <= today && $0.dueDate > cutoff }
    }
    private var aging8to30: [Invoice] {
        let a = Calendar.current.date(byAdding: .day, value: -7,  to: today)!
        let b = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        return (unpaidInvoices + overdueInvoices).filter { $0.dueDate <= a && $0.dueDate > b }
    }
    private var aging30plus: [Invoice] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        return (unpaidInvoices + overdueInvoices).filter { $0.dueDate <= cutoff }
    }

    private var avgDaysToPayment: Double? {
        let paid = invoices.filter { $0.status == .paid && $0.paidAt != nil }
        guard !paid.isEmpty else { return nil }
        let days = paid.compactMap { inv -> Double? in
            guard let paidAt = inv.paidAt else { return nil }
            return paidAt.timeIntervalSince(inv.createdAt) / 86400
        }
        guard !days.isEmpty else { return nil }
        return days.reduce(0, +) / Double(days.count)
    }

    // MARK: - Navigation helpers

    private func jobsForStatus(_ status: JobStatus) -> [Job] {
        switch status {
        case .completed:              return jobsCompleted
        case .scheduled, .inProgress: return jobsScheduled
        case .cancelled:              return jobsCancelled
        }
    }

    private func invoicesForStatus(_ status: InvoiceStatus) -> [Invoice] {
        switch status {
        case .paid:    return paidInvoices
        case .unpaid:  return unpaidInvoices
        case .overdue: return overdueInvoices
        }
    }

    // MARK: - Jobs data

    private var jobsThisMonth: [Job] {
        jobsStore.jobs.filter { currentMonthInterval.contains($0.date) }
    }
    private var jobsCompleted:  [Job] { jobsThisMonth.filter { $0.status == .completed } }
    private var jobsScheduled:  [Job] { jobsThisMonth.filter { $0.status == .scheduled || $0.status == .inProgress } }
    private var jobsCancelled:  [Job] { jobsThisMonth.filter { $0.status == .cancelled } }
    private var jobCompletionRate: Double {
        let denom = jobsCompleted.count + jobsCancelled.count
        guard denom > 0 else { return 0 }
        return Double(jobsCompleted.count) / Double(denom)
    }

    // MARK: - Revenue by service

    private var revenueByService: [(service: String, revenue: Double, jobCount: Int)] {
        let completed = jobsStore.jobs.filter { $0.status == .completed }
        var dict: [String: (Double, Int)] = [:]
        for job in completed {
            let key = job.serviceType.rawValue
            let e = dict[key] ?? (0, 0)
            dict[key] = (e.0 + job.price, e.1 + 1)
        }
        return dict.map { (service: $0.key, revenue: $0.value.0, jobCount: $0.value.1) }
            .sorted { $0.revenue > $1.revenue }
    }

    private var completedJobsAll: [Job] { jobsStore.jobs.filter { $0.status == .completed } }

    private var customServiceJobs: [Job] {
        completedJobsAll.filter {
            if case .custom = $0.serviceType { return true }
            return false
        }
    }

    private var totalRevenueAllTime: Double { revenueByService.reduce(0) { $0 + $1.revenue } }

    private var avgTicketAllTime: Double {
        let count = revenueByService.reduce(0) { $0 + $1.jobCount }
        guard count > 0 else { return 0 }
        return totalRevenueAllTime / Double(count)
    }

    private func serviceColor(at index: Int) -> Color {
        let palette: [Color] = [
            Color.sweeplyAccent,
            Color.sweeplyNavy,
            Color.sweeplyWarning,
            Color.sweeplySuccess,
            Color(hue: 0.08, saturation: 0.75, brightness: 0.80),
            Color(hue: 0.58, saturation: 0.70, brightness: 0.75),
        ]
        return palette[index % palette.count]
    }

    // MARK: - Payment methods

    private var paymentMethodStats: [(method: PaymentMethod, count: Int, total: Double)] {
        var dict: [PaymentMethod: (Int, Double)] = [:]
        for inv in paidInvoices {
            let m = inv.paymentMethod ?? .other
            let e = dict[m] ?? (0, 0)
            dict[m] = (e.0 + 1, e.1 + inv.total)
        }
        return dict.map { (method: $0.key, count: $0.value.0, total: $0.value.1) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ytdSummarySection
                    revenueProgressSection
                    sixMonthChartSection
                    cashflowSectionWithPopup
                    profitAndLossWithExpensesSection
                    revenueByServiceSection
                    jobsSummarySection
                    invoiceHealthSection
                    paymentMethodsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
            }
            .scrollDisabled(showForecastPopup)
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .overlay {
                if showForecastPopup, let week = popupWeek {
                    forecastPopupOverlay(week: week)
                }
            }
            .sheet(isPresented: $showOverviewPeriodFilter) {
                overviewPeriodFilterSheet
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
            .navigationTitle("Reports".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".translated()) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }

    // MARK: - Overview Period Filter Sheet

    private var overviewPeriodFilterSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Select Time Range".translated())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(OverviewPeriod.allCases, id: \.self) { period in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        overviewPeriodRaw = period.rawValue
                        selectedOverviewMonth = nil
                        showOverviewPeriodFilter = false
                    } label: {
                        HStack {
                            Text(periodLabel(for: period))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                            Spacer()
                            if period == overviewPeriod {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.sweeplyAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(period == overviewPeriod ? Color.sweeplyAccent.opacity(0.08) : Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(period == overviewPeriod ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .background(Color.sweeplyBackground.ignoresSafeArea())
    }

    private func periodLabel(for period: OverviewPeriod) -> String {
        switch period {
        case .oneMonth: return "Last Month".translated()
        case .threeMonth: return "Last 3 Months".translated()
        case .sixMonth: return "Last 6 Months".translated()
        case .twelveMonth: return "Last 12 Months".translated()
        }
    }

    // MARK: - Quick Stats

    private var ytdSummarySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                kpiBox(icon: "dollarsign.circle.fill", title: "Revenue".translated(), value: ytdRevenue.currency, color: Color.sweeplySuccess)
                kpiBox(icon: "minus.circle.fill", title: "Expenses".translated(), value: ytdExpenses.currency, color: Color.sweeplyDestructive)
                kpiBox(icon: "checkmark.circle.fill", title: "Net Profit".translated(), value: ytdNet.currency, color: ytdNet >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive)
                kpiBox(icon: "doc.text.fill", title: "Invoices Paid".translated(), value: "\(ytdInvoiceCount)", color: Color.sweeplyAccent)
                kpiBox(icon: "person.2.fill", title: "Active Clients".translated(), value: "\(activeClientsCount)", color: Color.sweeplyNavy)
                kpiBox(icon: "briefcase.fill", title: "Jobs This Month".translated(), value: "\(jobsThisMonthCount)", color: Color.sweeplyWarning)
                kpiBox(icon: "exclamationmark.triangle.fill", title: "Outstanding".translated(), value: unpaidTotal.currency, color: Color.sweeplyDestructive)
                kpiBox(icon: "calendar", title: "Scheduled".translated(), value: "\(scheduledJobsCount)", color: Color.sweeplySuccess)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var activeClientsCount: Int {
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        return jobsStore.jobs.filter { $0.status == .completed && $0.date >= sixMonthsAgo }
            .map { $0.clientId }.reduce(into: Set<UUID>()) { $0.insert($1) }.count
    }

    private var jobsThisMonthCount: Int {
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        return jobsStore.jobs.filter { $0.date >= startOfMonth && $0.status == .completed }.count
    }

    private var scheduledJobsCount: Int {
        jobsStore.jobs.filter { $0.status == .scheduled }.count
    }

    private func kpiBox(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 110, alignment: .leading)
        .padding(12)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Revenue Progress

    private var revenueProgressSection: some View {
        let collected = overviewBarData.map { $0.collected }.reduce(0, +)
        let scheduled = overviewBarData.map { $0.scheduled }.reduce(0, +)
        let total = collected + scheduled
        let progress = total > 0 ? collected / total : 0

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revenue Progress".translated())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    HStack(spacing: 4) {
                        Text("Collected".translated())
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplySuccess)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("Estimated".translated())
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(collected.currency)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplySuccess)
                    Text(total.currency)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.sweeplyBorder)
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.sweeplySuccess, Color.sweeplySuccess.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(progress), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(progress * 100))% " + "Collected".translated())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplySuccess)
                Spacer()
                if scheduled > 0 {
                    Text("\(scheduled.currency) " + "Estimated".translated())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyWarning)
                }
            }
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Revenue Overview (3M / 6M)

    private var sixMonthChartSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Revenue Overview".translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Collected vs outstanding".translated())
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showOverviewPeriodFilter = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(periodLabel(for: overviewPeriod))
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.sweeplyAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.sweeplyAccent.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }

                HStack(alignment: .bottom) {
                    let total = overviewBarData.reduce(0) { $0 + $1.collected }
                    let avg   = overviewBarData.isEmpty ? 0 : total / Double(overviewBarData.count)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total.currency)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: overviewPeriodRaw)
                        if overviewPeriod != .oneMonth {
                            Text("avg".translated() + " \(avg.currency) / " + "month".translated())
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                    Spacer()
                    if overviewPeriod != .oneMonth, let trend = overviewTrend { overviewTrendBadge(trend: trend) }
                }

                if overviewPeriod == .oneMonth, let bar = overviewBarData.first {
                    // Single month view - show collected vs outstanding as bar
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Collected".translated())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                Text(bar.collected.currency)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Outstanding".translated())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                Text(bar.scheduled.currency)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.sweeplyNavy.opacity(0.6))
                                    .monospacedDigit()
                            }
                        }
                        
                        let maxAmount = max(bar.collected, bar.scheduled, 1)
                        GeometryReader { geo in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.sweeplyAccent)
                                    .frame(width: geo.size.width * CGFloat(bar.collected / maxAmount) - 4)
                                    .frame(height: 24)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.sweeplyNavy.opacity(0.3))
                                    .frame(width: geo.size.width * CGFloat(bar.scheduled / maxAmount) - 4)
                                    .frame(height: 24)
                            }
                        }
                        .frame(height: 24)
                    }
                } else {
                    // Multi-month view - show trend chart
                    Chart {
                        ForEach(overviewBarData) { bar in
                            AreaMark(x: .value("Month", bar.month), y: .value("Collected", bar.collected), series: .value("S", "collected"))
                                .foregroundStyle(LinearGradient(colors: [Color.sweeplyAccent.opacity(0.22), Color.sweeplyAccent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Month", bar.month), y: .value("Collected", bar.collected), series: .value("S", "collected"))
                                .foregroundStyle(Color.sweeplyAccent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Month", bar.month), y: .value("Collected", bar.collected))
                                .foregroundStyle(Color.sweeplyAccent)
                                .symbolSize(selectedOverviewMonth == bar.month ? 64 : 28)
                            LineMark(x: .value("Month", bar.month), y: .value("Outstanding", bar.scheduled), series: .value("S", "outstanding"))
                                .foregroundStyle(Color.sweeplyNavy.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.sweeplyBorder.opacity(0.7))
                            AxisValueLabel().font(.system(size: 10, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.sweeplyBorder.opacity(0.5))
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(d.shortCurrency).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedOverviewMonth)
                    .frame(height: 160)
                    .animation(.easeInOut(duration: 0.3), value: overviewPeriodRaw)
                }

                if overviewPeriod != .oneMonth,
                   let month = selectedOverviewMonth,
                   let bar = overviewBarData.first(where: { $0.month == month }) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bar.month).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.sweeplyTextSub)
                            Text(bar.total.currency).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Color.sweeplyNavy)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.sweeplyAccent).frame(width: 6, height: 6)
                                Text(bar.collected.currency).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color.sweeplyNavy)
                            }
                            HStack(spacing: 6) {
                                Circle().fill(Color.sweeplyNavy.opacity(0.3)).frame(width: 6, height: 6)
                                Text(bar.scheduled.currency).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color.sweeplyNavy)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 16) {
                    legendItem(color: Color.sweeplyAccent, label: "Collected")
                    legendItem(color: Color.sweeplyNavy.opacity(0.3), label: "Outstanding")
                }
            }
        }
    }

    // MARK: - Cash-Flow Forecast

    private var cashflowForecastSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cash-Flow Forecast".translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Based on scheduled jobs & invoices".translated())
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    periodToggle(options: [8, 12].map { "\($0)W" }, selected: "\(forecastWeekCount)W") { raw in
                        let weeks = raw == "8W" ? 8 : 12
                        forecastWeekCount = weeks
                        selectedForecastWeekLabel = nil
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(forecastTotal.currency)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: forecastWeekCount)
                    }
                    Spacer()
                    if let sel = selectedForecastWeek {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(sel.total.currency)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("wk of".translated() + " \(sel.weekLabel)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .transition(.opacity)
                    }
                }

                // Scrollable chart — 52pt per bar so bars are never squeezed
                let chartWidth = max(CGFloat(forecastWeekCount) * 52, 320)
                ScrollView(.horizontal, showsIndicators: false) {
                    Chart(cashflowForecast) { week in
                        let isSelected = selectedForecastWeekLabel == week.weekLabel

                        // Highlight strip
                        if isSelected {
                            RectangleMark(x: .value("Week", week.weekLabel))
                                .foregroundStyle(Color.sweeplyAccent.opacity(0.12))
                                .cornerRadius(6)
                        }

                        BarMark(
                            x: .value("Week", week.weekLabel),
                            y: .value("Jobs", week.jobsAmount),
                            stacking: .standard
                        )
                        .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.55))
                        .cornerRadius(4)

                        BarMark(
                            x: .value("Week", week.weekLabel),
                            y: .value("Invoices", week.invoicesAmount),
                            stacking: .standard
                        )
                        .foregroundStyle(isSelected ? Color.sweeplyAccent : Color.sweeplyAccent.opacity(0.50))
                        .cornerRadius(4)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { _ in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            if let weekLabel: String = proxy.value(atX: value.location.x) {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    selectedForecastWeekLabel = weekLabel
                                                }
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.4)
                                        .onEnded { _ in
                                            if let selectedLabel = selectedForecastWeekLabel,
                                               let week = cashflowForecast.first(where: { $0.weekLabel == selectedLabel }) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                popupWeek = week
                                                showForecastPopup = true
                                            }
                                        }
                                )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) {
                            AxisValueLabel()
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.sweeplyBorder.opacity(0.7))
                            AxisValueLabel()
                                .font(.system(size: 9))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                    .frame(width: chartWidth, height: 180)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 16) {
                    legendDot(color: Color.sweeplyNavy.opacity(0.75), label: "Scheduled jobs")
                    legendDot(color: Color.sweeplyAccent.opacity(0.65), label: "Outstanding invoices")
                }

                if forecastTotal == 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("Schedule jobs or send invoices to see your forecast.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var cashflowSectionWithPopup: some View {
        cashflowForecastSection
    }

    // MARK: - Forecast Popup

    @ViewBuilder
    private func forecastPopupOverlay(week: ForecastWeek) -> some View {
        ZStack {
            // Dark background with blur - covers entire screen
            Rectangle()
                .fill(Color.sweeplyNavy.opacity(0.5))
                .ignoresSafeArea()
            
            // Blur effect layer
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            // Popup card
            VStack(spacing: 16) {
                // Header with date range
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyAccent)
                        Text(week.weekLabel)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    
                    Text(week.weekStart, style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                Divider()

                // Detailed breakdown
                VStack(spacing: 12) {
                    // Scheduled Jobs
                    popupRow(
                        icon: "calendar.badge.clock",
                        iconColor: Color.sweeplyNavy,
                        iconBg: Color.sweeplyNavy.opacity(0.10),
                        title: "Scheduled Jobs",
                        subtitle: "\(week.jobCount) job\(week.jobCount == 1 ? "" : "s")",
                        amount: week.jobsAmount,
                        amountColor: Color.sweeplyNavy
                    )

                    // Outstanding Invoices
                    popupRow(
                        icon: "doc.text.fill",
                        iconColor: Color.sweeplyAccent,
                        iconBg: Color.sweeplyAccent.opacity(0.10),
                        title: "Outstanding Invoices",
                        subtitle: "\(week.invoiceCount) invoice\(week.invoiceCount == 1 ? "" : "s")",
                        amount: week.invoicesAmount,
                        amountColor: Color.sweeplyAccent
                    )
                }

                Divider()

                // Total & Comparison
                VStack(spacing: 8) {
                    HStack {
                        Text("Total Projected".translated())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text(week.total.currency)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplySuccess)
                    }
                    
                    // Comparison to average
                    let avg = forecastAvgWeekly
                    let diff = week.total - avg
                    let percentChange = avg > 0 ? (diff / avg) * 100 : 0
                    HStack {
                        Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(abs(Int(percentChange)))% vs avg")
                            .font(.system(size: 11, weight: .medium))
                        Text("(\(avg.currency)/wk)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .foregroundStyle(diff >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive)
                }

                Divider()

                // Forecast period info
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text("\(forecastWeekCount) week forecast")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Spacer()
                    Text("\(cashflowForecast.count) weeks shown")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                }

                // Close button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showForecastPopup = false
                        popupWeek = nil
                    }
                } label: {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Close".translated())
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(24)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            .shadow(color: Color.sweeplyNavy.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Popup Row Helper

    private func popupRow(icon: String, iconColor: Color, iconBg: Color, title: String, subtitle: String, amount: Double, amountColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBg)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Text(amount.currency)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(amountColor)
        }
    }

    // MARK: - Profit & Loss

    private var profitAndLossSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profit & Loss".translated().uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.8)
                        Text(plPeriod.rawValue.translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    Spacer()
                    periodToggle(options: PLPeriod.allCases.map { $0.rawValue }, selected: plPeriod.rawValue) { raw in
                        if let p = PLPeriod(rawValue: raw) { plPeriod = p }
                    }
                }

                VStack(spacing: 0) {
                    plRow(label: "Revenue".translated(),    value: plIncome,    color: Color.sweeplySuccess,                                         icon: "arrow.down.circle.fill",           isBold: false)
                    Divider().padding(.leading, 40)
                    plRow(label: "Expenses".translated(),   value: -plExpenses, color: Color.sweeplyDestructive,                                     icon: "arrow.up.circle.fill",             isBold: false)
                    Divider()
                    plRow(label: "Net Profit".translated(), value: plNet,       color: plNet >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive, icon: plNet >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill", isBold: true)
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
    }

    private func plRow(label: String, value: Double, color: Color, icon: String, isBold: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 14, weight: isBold ? .bold : .medium))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
            Text(value < 0 ? "-\((-value).currency)" : value.currency)
                .font(.system(size: 14, weight: isBold ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: - Combined P&L + Expenses Section

    private var profitAndLossWithExpensesSection: some View {
        VStack(spacing: 0) {
            // Profit & Loss - top part
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profit & Loss".translated().uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.8)
                        Text(plPeriod.rawValue.translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    Spacer()
                    periodToggle(options: PLPeriod.allCases.map { $0.rawValue }, selected: plPeriod.rawValue) { raw in
                        if let p = PLPeriod(rawValue: raw) { plPeriod = p }
                    }
                }

                VStack(spacing: 0) {
                    plRow(label: "Revenue".translated(),    value: plIncome,    color: Color.sweeplySuccess,                                         icon: "arrow.down.circle.fill",           isBold: false)
                    Divider().padding(.leading, 40)
                    plRow(label: "Expenses".translated(),   value: -plExpenses, color: Color.sweeplyDestructive,                                     icon: "arrow.up.circle.fill",             isBold: false)
                    Divider()
                    plRow(label: "Net Profit".translated(), value: plNet,       color: plNet >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive, icon: plNet >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill", isBold: true)
                }
            }
            .padding(16)

            // Divider between sections
            Rectangle()
                .fill(Color.sweeplyBorder)
                .frame(height: 1)

            // Expenses by Category - connected bottom part
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXPENSES BY CATEGORY".translated())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.8)
                        Text(plPeriod.rawValue.translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    Spacer()
                    periodToggle(options: PLPeriod.allCases.map { $0.rawValue }, selected: plPeriod.rawValue) { raw in
                        if let p = PLPeriod(rawValue: raw) { plPeriod = p }
                    }
                }

                let categories   = expenseStore.byCategory(in: plPeriodInterval)
                let priorCats    = Dictionary(uniqueKeysWithValues: expenseStore.byCategory(in: plPriorInterval))
                let monthTotal   = categories.reduce(0) { $0 + $1.1 }
                let priorTotal   = priorCats.values.reduce(0, +)

                if categories.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "cart.badge.questionmark")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("No expenses recorded this period.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.vertical, 8)
                } else {
                    let maxAmount = categories.map { $0.1 }.max() ?? 1
                    VStack(spacing: 12) {
                        ForEach(categories, id: \.0) { cat, amount in
                            categoryRow(cat: cat, amount: amount, maxAmount: maxAmount, prior: priorCats[cat])
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total".translated())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        if priorTotal > 0 {
                            let delta = monthTotal - priorTotal
                            deltaBadge(delta: delta, invert: true)
                        }
                        Text(monthTotal.currency)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Expenses by Category

    private var expensesByCategorySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPENSES BY CATEGORY".translated())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("This month".translated())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                let categories   = expenseStore.byCategory(in: currentMonthInterval)
                let priorCats    = Dictionary(uniqueKeysWithValues: expenseStore.byCategory(in: priorMonthInterval))
                let monthTotal   = categories.reduce(0) { $0 + $1.1 }
                let priorTotal   = priorCats.values.reduce(0, +)

                if categories.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "cart.badge.questionmark")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("No expenses recorded this month.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.vertical, 8)
                } else {
                    let maxAmount = categories.map { $0.1 }.max() ?? 1
                    VStack(spacing: 12) {
                        ForEach(categories, id: \.0) { cat, amount in
                            categoryRow(cat: cat, amount: amount, maxAmount: maxAmount, prior: priorCats[cat])
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total".translated())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        if priorTotal > 0 {
                            let delta = monthTotal - priorTotal
                            deltaBadge(delta: delta, invert: true)
                        }
                        Text(monthTotal.currency)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
        }
    }

    private func categoryRow(cat: ExpenseCategory, amount: Double, maxAmount: Double, prior: Double?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(expenseCategoryColor(cat).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: cat.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(expenseCategoryColor(cat))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(cat.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
                    Spacer()
                    if let p = prior {
                        deltaBadge(delta: amount - p, invert: true)
                    }
                    Text(amount.currency)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.sweeplyBorder.opacity(0.6)).frame(height: 5)
                        Capsule().fill(expenseCategoryColor(cat))
                            .frame(width: geo.size.width * CGFloat(amount / maxAmount), height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private func expenseCategoryColor(_ cat: ExpenseCategory) -> Color {
        switch cat {
        case .supplies:  return Color(hue: 0.58, saturation: 0.70, brightness: 0.75)
        case .fuel:      return Color.sweeplyWarning
        case .equipment: return Color(hue: 0.55, saturation: 0.65, brightness: 0.70)
        case .insurance: return Color.sweeplyAccent
        case .marketing: return Color(hue: 0.08, saturation: 0.75, brightness: 0.80)
        case .other:     return Color.sweeplyTextSub
        }
    }

    // MARK: - Revenue by Service

    private var revenueByServiceSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {

                // Header + View button
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REVENUE BY SERVICE".translated())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.8)
                        Text("All completed jobs".translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    Spacer()
                    NavigationLink {
                        RevenueDetailView(
                            revenueByService: revenueByService,
                            completedJobs: completedJobsAll,
                            customJobs: customServiceJobs,
                            serviceColorAt: serviceColor
                        )
                    } label: {
                        HStack(spacing: 3) {
                            Text("View".translated())
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .buttonStyle(.plain)
                }

                if revenueByService.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "briefcase")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("Complete jobs to see revenue by service.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.vertical, 8)
                } else {
                    TabView(selection: $revenueSlide) {
                        revenueServiceBarsSlide.tag(0)
                        revenueAddOnsSlide.tag(1)
                        revenuePieSlide.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 210)

                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { idx in
                            Capsule()
                                .fill(idx == revenueSlide ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.8))
                                .frame(width: idx == revenueSlide ? 18 : 8, height: 8)
                                .animation(.easeInOut(duration: 0.2), value: revenueSlide)
                        }
                        Spacer()
                        Text("\(revenueSlide + 1) / 3")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
            }
        }
    }

    // Slide 1 — Revenue bars
    private var revenueServiceBarsSlide: some View {
        let maxRev = revenueByService.map { $0.revenue }.max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MAIN SERVICES".translated())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.6)
                Spacer()
                Text("\(revenueByService.count) service\(revenueByService.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            .padding(.bottom, 10)
            
            VStack(spacing: 10) {
            ForEach(Array(revenueByService.prefix(4).enumerated()), id: \.element.service) { idx, item in
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(serviceColor(at: idx).opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: serviceIconFor(item.service))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(serviceColor(at: idx))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.service)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.jobCount)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text(item.revenue.currency)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(serviceColor(at: idx))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 5)
                                Capsule().fill(serviceColor(at: idx))
                                    .frame(width: geo.size.width * CGFloat(item.revenue / maxRev), height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            }
        }
    }

    // Slide 2 — Add-ons & extras (custom service jobs)
    private var revenueAddOnsSlide: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EXTRAS & ADD-ONS".translated())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.6)
                Spacer()
                Text("\(customServiceJobs.count) job\(customServiceJobs.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            .padding(.bottom, 10)

            if customServiceJobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                    Text("No custom or add-on services yet".translated())
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let addOnTotal = customServiceJobs.reduce(0) { $0 + $1.price }
                HStack(spacing: 0) {
                    statChip(label: "Revenue", value: addOnTotal.currency, color: Color.sweeplyAccent)
                    Divider().frame(height: 36).padding(.horizontal, 12)
                    statChip(label: "Avg Ticket",
                             value: (addOnTotal / Double(customServiceJobs.count)).currency,
                             color: Color.sweeplyNavy)
                }
                .padding(.bottom, 10)

                VStack(spacing: 6) {
                    ForEach(customServiceJobs.sorted { $0.price > $1.price }.prefix(3)) { job in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.sweeplyAccent.opacity(0.10)).frame(width: 28, height: 28)
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.sweeplyAccent)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.serviceType.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyNavy)
                                    .lineLimit(1)
                                Text(job.clientName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(job.price.currency)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // Slide 3 — Pie / donut chart
    @ViewBuilder
    private var revenuePieSlide: some View {
        if #available(iOS 17.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SERVICE BREAKDOWN".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.6)
                    Spacer()
                }
                .padding(.bottom, 10)
                
                HStack(alignment: .center, spacing: 16) {
                Chart(Array(revenueByService.prefix(6).enumerated()), id: \.element.service) { idx, item in
                    SectorMark(
                        angle: .value("Jobs", item.jobCount),
                        innerRadius: .ratio(0.54),
                        angularInset: 1.5
                    )
                    .foregroundStyle(serviceColor(at: idx))
                    .cornerRadius(3)
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(revenueByService.prefix(5).enumerated()), id: \.element.service) { idx, item in
                        let total = revenueByService.reduce(0) { $0 + $1.jobCount }
                        let pct = total > 0 ? Int(Double(item.jobCount) / Double(total) * 100) : 0
                        HStack(spacing: 6) {
                            Circle().fill(serviceColor(at: idx)).frame(width: 7, height: 7)
                            Text(item.service)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(1)
                            Spacer()
                            Text("\(pct)%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
        } else {
            revenueServiceBarsSlide
        }
    }

    private func statChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func serviceIconFor(_ service: String) -> String {
        switch service {
        case "Standard Clean": return "house.fill"
        case "Deep Clean":     return "sparkles"
        case "Move In/Out":    return "shippingbox.fill"
        case "Post Construction": return "hammer.fill"
        case "Office Clean":  return "building.2.fill"
        default:               return "wrench.and.screwdriver.fill"
        }
    }

    // MARK: - Jobs Summary

    private var jobsSummarySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOBS".translated())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("This month".translated())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        JobsDetailListView(status: .completed, jobs: jobsCompleted)
                    } label: {
                        invoiceStatBox(label: "Completed", count: jobsCompleted.count,
                                       total: jobsCompleted.reduce(0) { $0 + $1.price },
                                       color: Color.sweeplySuccess, showChevron: true)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        JobsDetailListView(status: .scheduled, jobs: jobsScheduled)
                    } label: {
                        invoiceStatBox(label: "Scheduled", count: jobsScheduled.count,
                                       total: jobsScheduled.reduce(0) { $0 + $1.price },
                                       color: Color.sweeplyAccent, showChevron: true)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        JobsDetailListView(status: .cancelled, jobs: jobsCancelled)
                    } label: {
                        invoiceStatBox(label: "Cancelled", count: jobsCancelled.count,
                                       total: nil,
                                       color: Color.sweeplyDestructive, showChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                if jobsCompleted.count + jobsCancelled.count > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Completion Rate".translated())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Spacer()
                            Text(String(format: "%.0f%%", jobCompletionRate * 100))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 8)
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.sweeplySuccess)
                                    .frame(width: geo.size.width * CGFloat(jobCompletionRate), height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }

    // MARK: - Invoice Health

    private var invoiceHealthSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("INVOICE HEALTH".translated())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)

                HStack(spacing: 10) {
                    NavigationLink {
                        InvoicesDetailListView(status: .paid, invoices: paidInvoices)
                    } label: {
                        invoiceStatBox(label: "Paid", count: paidInvoices.count,
                                       total: paidTotal, color: Color.sweeplySuccess, showChevron: true)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        InvoicesDetailListView(status: .unpaid, invoices: unpaidInvoices)
                    } label: {
                        invoiceStatBox(label: "Outstanding", count: unpaidInvoices.count,
                                       total: unpaidTotal, color: Color.sweeplyWarning, showChevron: true)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        InvoicesDetailListView(status: .overdue, invoices: overdueInvoices)
                    } label: {
                        invoiceStatBox(label: "Overdue", count: overdueInvoices.count,
                                       total: overdueTotal, color: Color.sweeplyDestructive, showChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                // Collection rate
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Collection Rate".translated())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(String(format: "%.0f%%", collectionRate * 100))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 8)
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.sweeplyAccent)
                                .frame(width: geo.size.width * CGFloat(collectionRate), height: 8)
                        }
                    }
                    .frame(height: 8)
                }

                // Aging breakdown (only shown if there are outstanding/overdue)
                let hasAging = !unpaidInvoices.isEmpty || !overdueInvoices.isEmpty
                if hasAging {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("INVOICE AGING".translated())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.6)
                            .padding(.bottom, 4)

                        agingRow(label: "Not due yet".translated(),      invoices: agingNotDueYet, color: Color.sweeplyAccent)
                        agingRow(label: "1–7 days overdue".translated(), invoices: aging1to7,      color: Color.sweeplyWarning)
                        agingRow(label: "8–30 days".translated(),        invoices: aging8to30,     color: Color(hue: 0.07, saturation: 0.75, brightness: 0.78))
                        agingRow(label: "30+ days".translated(),         invoices: aging30plus,    color: Color.sweeplyDestructive)
                    }
                    .padding(12)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                }

                // Avg days to payment
                if let avg = avgDaysToPayment {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("Avg. time to payment".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(String(format: "%.0f days", avg))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .padding(12)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func agingRow(label: String, invoices: [Invoice], color: Color) -> some View {
        if !invoices.isEmpty {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Text("\(invoices.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.75))
                    .clipShape(Capsule())
                Text(invoices.reduce(0) { $0 + $1.total }.currency)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: 72, alignment: .trailing)
            }
        }
    }

    // MARK: - Payment Methods

    private var paymentMethodsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    if !paymentMethodStats.isEmpty {
                        NavigationLink(destination: PaymentMethodsListView()) {
                            Text("View All".translated())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyAccent)
                        }
                    }
                }

                if paymentMethodStats.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("No paid invoices with payment method recorded.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(paymentMethodStats.enumerated()), id: \.element.method) { idx, stat in
                            paymentMethodRow(stat: stat)
                            if idx < paymentMethodStats.count - 1 { Divider().padding(.leading, 46) }
                        }
                    }
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }

    private func paymentMethodRow(stat: (method: PaymentMethod, count: Int, total: Double)) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.sweeplyAccent.opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: stat.method.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            Text(stat.method.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
            Text("\(stat.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.sweeplyNavy.opacity(0.45))
                .clipShape(Capsule())
            Text(stat.total.currency)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Shared Helpers

    private func invoiceStatBox(label: String, count: Int, total: Double?, color: Color, showChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                }
            }
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.sweeplyNavy)
            if let t = total {
                Text(t.currency)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
    }

    /// Generic pill-style toggle used across sections.
    private func periodToggle(options: [String], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { onSelect(option) }
                } label: {
                    Text(option)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected == option ? .white : Color.sweeplyTextSub)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selected == option {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.sweeplyNavy)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.sweeplyBorder.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func deltaBadge(delta: Double, invert: Bool) -> some View {
        let isPositive = delta >= 0
        // invert = true means higher is bad (expenses)
        let isGood = invert ? !isPositive : isPositive
        let color: Color = isGood ? Color.sweeplySuccess : Color.sweeplyDestructive
        let prefix = isPositive ? "+" : ""
        return Text("\(prefix)\(delta.shortCurrency)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func overviewTrendBadge(trend: Double) -> some View {
        let isUp = trend >= 0
        let color: Color = isUp ? Color.sweeplySuccess : Color.sweeplyDestructive
        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .bold))
            Text(String(format: "%.0f%%", abs(trend * 100))).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.sweeplyTextSub)
        }
    }
}

// MARK: - Supporting Types

struct MonthlyBar: Identifiable {
    var id: String { month }
    let month: String
    let collected: Double
    let scheduled: Double
    var total: Double { collected + scheduled }
}

extension Double {
    var shortCurrency: String {
        if self >= 1000 { return "$\(String(format: "%.1f", self / 1000))k" }
        return "$\(Int(self))"
    }
}
