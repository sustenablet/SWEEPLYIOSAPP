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

    // MARK: - Enums

    enum OverviewPeriod: String, CaseIterable {
        case threeMonth = "3M"
        case sixMonth   = "6M"
    }

    enum PLPeriod: String, CaseIterable {
        case thisMonth = "Month"
        case lastMonth = "Last Mo."
        case ytd       = "Year"
    }

    // MARK: - Intervals

    private var currentMonthInterval: DateInterval {
        let cal = Calendar.current
        return cal.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), duration: 0)
    }

    private var priorMonthInterval: DateInterval {
        let cal = Calendar.current
        guard let priorStart = cal.date(byAdding: .month, value: -1, to: currentMonthInterval.start),
              let interval = cal.dateInterval(of: .month, for: priorStart)
        else { return DateInterval(start: Date(), duration: 0) }
        return interval
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
        let count = overviewPeriod == .threeMonth ? 3 : 6
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
                    sixMonthChartSection
                    cashflowForecastSection
                    profitAndLossSection
                    expensesByCategorySection
                    revenueByServiceSection
                    jobsSummarySection
                    invoiceHealthSection
                    paymentMethodsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }

    // MARK: - YTD Summary

    private var ytdSummarySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("YEAR TO DATE · \(currentYear)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)

                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 10) {
                    ytdStatCell(label: "Revenue",       value: ytdRevenue.currency,           color: Color.sweeplySuccess)
                    ytdStatCell(label: "Expenses",      value: ytdExpenses.currency,           color: Color.sweeplyDestructive)
                    ytdStatCell(label: "Net Profit",    value: ytdNet.currency,                color: ytdNet >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive)
                    ytdStatCell(label: "Invoices Paid", value: "\(ytdInvoiceCount)",            color: Color.sweeplyAccent)
                }
            }
        }
    }

    private func ytdStatCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Revenue Overview (3M / 6M)

    private var sixMonthChartSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Revenue Overview")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Collected vs outstanding")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    periodToggle(options: OverviewPeriod.allCases.map { $0.rawValue }, selected: overviewPeriod.rawValue) { raw in
                        overviewPeriodRaw = raw
                        selectedOverviewMonth = nil
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
                        Text("avg \(avg.currency) / month")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    if let trend = overviewTrend { overviewTrendBadge(trend: trend) }
                }

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

                if let month = selectedOverviewMonth,
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
                        Text("Cash-Flow Forecast")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Based on scheduled jobs & invoices")
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
                        Text("projected over \(forecastWeekCount) weeks · avg \(forecastAvgWeekly.currency)/wk")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    if let sel = selectedForecastWeek {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(sel.total.currency)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("wk of \(sel.weekLabel)")
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
                    .chartXSelection(value: $selectedForecastWeekLabel)
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
                        Text("Schedule jobs or send invoices to see your forecast.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Profit & Loss

    private var profitAndLossSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PROFIT & LOSS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.8)
                        Text(plPeriod.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    Spacer()
                    periodToggle(options: PLPeriod.allCases.map { $0.rawValue }, selected: plPeriod.rawValue) { raw in
                        if let p = PLPeriod(rawValue: raw) { plPeriod = p }
                    }
                }

                VStack(spacing: 0) {
                    plRow(label: "Revenue",    value: plIncome,    color: Color.sweeplySuccess,                                         icon: "arrow.down.circle.fill",           isBold: false)
                    Divider().padding(.leading, 40)
                    plRow(label: "Expenses",   value: -plExpenses, color: Color.sweeplyDestructive,                                     icon: "arrow.up.circle.fill",             isBold: false)
                    Divider()
                    plRow(label: "Net Profit", value: plNet,       color: plNet >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive, icon: plNet >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill", isBold: true)
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

    // MARK: - Expenses by Category

    private var expensesByCategorySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPENSES BY CATEGORY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("This month")
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
                        Text("No expenses recorded this month.")
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
                        Text("Total")
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
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REVENUE BY SERVICE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("All completed jobs")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                if revenueByService.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "briefcase")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("Complete jobs to see revenue by service.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.vertical, 8)
                } else {
                    let maxRev = revenueByService.map { $0.revenue }.max() ?? 1
                    VStack(spacing: 12) {
                        ForEach(revenueByService, id: \.service) { item in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.sweeplyAccent.opacity(0.10))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.sweeplyAccent)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.service)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color.sweeplyNavy)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(item.jobCount) job\(item.jobCount == 1 ? "" : "s")")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                        Text(item.revenue.currency)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(Color.sweeplyNavy)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.sweeplyBorder.opacity(0.6)).frame(height: 5)
                                            Capsule().fill(Color.sweeplyAccent)
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
        }
    }

    // MARK: - Jobs Summary

    private var jobsSummarySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOBS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("This month")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                HStack(spacing: 10) {
                    invoiceStatBox(label: "Completed", count: jobsCompleted.count,
                                   total: jobsCompleted.reduce(0) { $0 + $1.price },
                                   color: Color.sweeplySuccess)
                    invoiceStatBox(label: "Scheduled",  count: jobsScheduled.count,
                                   total: jobsScheduled.reduce(0) { $0 + $1.price },
                                   color: Color.sweeplyAccent)
                    invoiceStatBox(label: "Cancelled",  count: jobsCancelled.count,
                                   total: nil,
                                   color: Color.sweeplyDestructive)
                }

                if jobsCompleted.count + jobsCancelled.count > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Completion Rate")
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
                Text("INVOICE HEALTH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)

                HStack(spacing: 10) {
                    invoiceStatBox(label: "Paid",        count: paidInvoices.count,    total: paidTotal,    color: Color.sweeplySuccess)
                    invoiceStatBox(label: "Outstanding", count: unpaidInvoices.count,   total: unpaidTotal,  color: Color.sweeplyWarning)
                    invoiceStatBox(label: "Overdue",     count: overdueInvoices.count,  total: overdueTotal, color: Color.sweeplyDestructive)
                }

                // Collection rate
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Collection Rate")
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
                        Text("INVOICE AGING")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.6)
                            .padding(.bottom, 4)

                        agingRow(label: "Not due yet",      invoices: agingNotDueYet, color: Color.sweeplyAccent)
                        agingRow(label: "1–7 days overdue", invoices: aging1to7,      color: Color.sweeplyWarning)
                        agingRow(label: "8–30 days",        invoices: aging8to30,     color: Color(hue: 0.07, saturation: 0.75, brightness: 0.78))
                        agingRow(label: "30+ days",         invoices: aging30plus,    color: Color.sweeplyDestructive)
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
                        Text("Avg. time to payment")
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
                Text("PAYMENT METHODS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)

                if paymentMethodStats.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("No paid invoices with payment method recorded.")
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

    private func invoiceStatBox(label: String, count: Int, total: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
            }
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.sweeplyNavy)
            if let t = total {
                Text(t.currency)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
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
