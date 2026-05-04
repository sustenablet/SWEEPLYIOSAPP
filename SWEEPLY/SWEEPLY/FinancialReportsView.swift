import SwiftUI
import Charts

struct FinancialReportsView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(InvoicesStore.self)       private var invoicesStore
    @Environment(ExpenseStore.self)        private var expenseStore
    @Environment(JobsStore.self)           private var jobsStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    // ── State (moved from FinancesView) ──
    @AppStorage("financesOverviewPeriod") private var overviewPeriodRaw: String = OverviewPeriod.sixMonth.rawValue
    @State private var selectedOverviewMonth: String? = nil
    @AppStorage("cashflowForecastWeeks") private var forecastWeekCount: Int = 8
    @State private var selectedForecastWeek: ForecastWeek? = nil
    @State private var selectedCashflowBar: String? = nil
    @State private var selectedCashflowValue: Double = 0

    enum OverviewPeriod: String, CaseIterable {
        case threeMonth = "3M"
        case sixMonth   = "6M"
    }

    // MARK: - Computed helpers

    private var invoices: [Invoice] { invoicesStore.invoices }

    private var overviewPeriod: OverviewPeriod { OverviewPeriod(rawValue: overviewPeriodRaw) ?? .sixMonth }

    private var currentMonthInterval: DateInterval {
        let cal = Calendar.current
        return cal.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), duration: 0)
    }

    private var overviewBarData: [MonthlyBar] {
        let count = overviewPeriod == .threeMonth ? 3 : 6
        let calendar = Calendar.current
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return (0..<count).reversed().compactMap { offset -> MonthlyBar? in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: now),
                  let interval = calendar.dateInterval(of: .month, for: monthStart) else { return nil }
            let label = f.string(from: interval.start)
            let collected = invoices.filter {
                $0.status == .paid && $0.createdAt >= interval.start && $0.createdAt < interval.end
            }.reduce(0) { $0 + $1.total }
            let outstanding = invoices.filter {
                $0.status != .paid && $0.createdAt >= interval.start && $0.createdAt < interval.end
            }.reduce(0) { $0 + $1.total }
            return MonthlyBar(month: label, collected: collected, scheduled: outstanding)
        }
    }

    private var overviewTrend: Double? {
        guard overviewBarData.count >= 2 else { return nil }
        let last = overviewBarData[overviewBarData.count - 1].collected
        let prev = overviewBarData[overviewBarData.count - 2].collected
        guard prev > 0 else { return nil }
        return (last - prev) / prev
    }

    private var cashflowForecast: [ForecastWeek] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let upcomingJobs = jobsStore.jobs.filter { $0.status == .scheduled && $0.date >= today }
        let unpaidInvoices = invoicesStore.invoices.filter { $0.status == .unpaid && $0.dueDate >= today }

        return (0..<forecastWeekCount).map { offset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: today) ?? today
            let weekEnd   = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let interval  = DateInterval(start: weekStart, end: weekEnd)

            let weekJobs     = upcomingJobs.filter { interval.contains($0.date) }
            let weekInvoices = unpaidInvoices.filter { interval.contains($0.dueDate) }

            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"

            return ForecastWeek(
                weekStart: weekStart,
                weekLabel: fmt.string(from: weekStart),
                jobsAmount: weekJobs.reduce(0) { $0 + $1.price },
                invoicesAmount: weekInvoices.reduce(0) { $0 + $1.amount },
                jobCount: weekJobs.count,
                invoiceCount: weekInvoices.count
            )
        }
    }

    private var forecastTotal: Double { cashflowForecast.reduce(0) { $0 + $1.total } }
    private var forecastAvgWeekly: Double {
        cashflowForecast.isEmpty ? 0 : forecastTotal / Double(cashflowForecast.count)
    }
    private var forecastMax: Double {
        max(cashflowForecast.map { $0.total }.max() ?? 1, 1)
    }

    // P&L data
    private var monthIncome: Double {
        invoices.filter { $0.status == .paid && currentMonthInterval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }
    private var monthExpenses: Double { expenseStore.total(in: currentMonthInterval) }
    private var netProfit: Double { monthIncome - monthExpenses }

    private var priorMonthIncome: Double {
        let cal = Calendar.current
        guard let priorStart = cal.date(byAdding: .month, value: -1, to: currentMonthInterval.start),
              let interval = cal.dateInterval(of: .month, for: priorStart) else { return 0 }
        return invoices.filter { $0.status == .paid && interval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }

    // Invoice health data
    private var paidInvoices: [Invoice] { invoices.filter { $0.status == .paid } }
    private var unpaidInvoices: [Invoice] { invoices.filter { $0.status == .unpaid } }
    private var overdueInvoices: [Invoice] { invoices.filter { $0.status == .overdue } }
    private var paidTotal: Double { paidInvoices.reduce(0) { $0 + $1.total } }
    private var unpaidTotal: Double { unpaidInvoices.reduce(0) { $0 + $1.total } }
    private var overdueTotal: Double { overdueInvoices.reduce(0) { $0 + $1.total } }
    private var collectionRate: Double {
        let total = paidTotal + unpaidTotal + overdueTotal
        guard total > 0 else { return 0 }
        return paidTotal / total
    }

    // Top clients
    private var topClients: [(name: String, total: Double)] {
        var dict: [String: Double] = [:]
        for inv in invoices where inv.status == .paid {
            dict[inv.clientName, default: 0] += inv.total
        }
        return dict.map { (name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { $0 }
    }

    // Payment methods
    private var paymentMethodStats: [(method: PaymentMethod, count: Int, total: Double)] {
        let paid = invoices.filter { $0.status == .paid }
        var dict: [PaymentMethod: (count: Int, total: Double)] = [:]
        for inv in paid {
            let m = inv.paymentMethod ?? .other
            let existing = dict[m] ?? (count: 0, total: 0)
            dict[m] = (count: existing.count + 1, total: existing.total + inv.total)
        }
        return dict.map { (method: $0.key, count: $0.value.count, total: $0.value.total) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sixMonthChartSection
                    cashflowForecastSection
                    profitAndLossSection
                    expensesByCategorySection
                    invoiceHealthSection
                    paymentMethodsSection
                    topClientsSection
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
                    HStack(spacing: 0) {
                        ForEach(OverviewPeriod.allCases, id: \.self) { period in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    overviewPeriodRaw = period.rawValue
                                    selectedOverviewMonth = nil
                                }
                            } label: {
                                Text(period.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(overviewPeriod == period ? .white : Color.sweeplyTextSub)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background {
                                        if overviewPeriod == period {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.sweeplyNavy)
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

                HStack(alignment: .bottom) {
                    let total = overviewBarData.reduce(0) { $0 + $1.collected }
                    let avg = overviewBarData.isEmpty ? 0 : total / Double(overviewBarData.count)
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
                    if let trend = overviewTrend {
                        overviewTrendBadge(trend: trend)
                    }
                }

                Chart {
                    ForEach(overviewBarData) { bar in
                        AreaMark(
                            x: .value("Month", bar.month),
                            y: .value("Collected", bar.collected),
                            series: .value("S", "collected")
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.sweeplyAccent.opacity(0.22), Color.sweeplyAccent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Month", bar.month),
                            y: .value("Collected", bar.collected),
                            series: .value("S", "collected")
                        )
                        .foregroundStyle(Color.sweeplyAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Month", bar.month),
                            y: .value("Collected", bar.collected)
                        )
                        .foregroundStyle(Color.sweeplyAccent)
                        .symbolSize(selectedOverviewMonth == bar.month ? 64 : 28)

                        LineMark(
                            x: .value("Month", bar.month),
                            y: .value("Outstanding", bar.scheduled),
                            series: .value("S", "outstanding")
                        )
                        .foregroundStyle(Color.sweeplyNavy.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.sweeplyBorder.opacity(0.7))
                        AxisValueLabel()
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.sweeplyBorder.opacity(0.5))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(d.shortCurrency)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
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
                            Text(bar.month)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text(bar.total.currency)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.sweeplyAccent).frame(width: 6, height: 6)
                                Text(bar.collected.currency)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyNavy)
                            }
                            HStack(spacing: 6) {
                                Circle().fill(Color.sweeplyNavy.opacity(0.3)).frame(width: 6, height: 6)
                                Text(bar.scheduled.currency)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyNavy)
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
                    HStack(spacing: 0) {
                        ForEach([8, 12], id: \.self) { weeks in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    forecastWeekCount = weeks
                                    selectedForecastWeek = nil
                                }
                            } label: {
                                Text("\(weeks)W")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(forecastWeekCount == weeks ? .white : Color.sweeplyTextSub)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background {
                                        if forecastWeekCount == weeks {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.sweeplyNavy)
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
                            Text("week of \(sel.weekLabel)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .transition(.opacity)
                    }
                }

                Chart(cashflowForecast) { week in
                    BarMark(
                        x: .value("Week", week.weekLabel),
                        y: .value("Jobs", week.jobsAmount),
                        stacking: .standard
                    )
                    .foregroundStyle(Color.sweeplyNavy.opacity(0.75))
                    .cornerRadius(4)

                    BarMark(
                        x: .value("Week", week.weekLabel),
                        y: .value("Invoices", week.invoicesAmount),
                        stacking: .standard
                    )
                    .foregroundStyle(Color.sweeplyAccent.opacity(0.65))
                    .cornerRadius(4)
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let x = val.location.x - geo[proxy.plotFrame!].origin.x
                                        if let label: String = proxy.value(atX: x) {
                                            if let week = cashflowForecast.first(where: { $0.weekLabel == label }) {
                                                withAnimation(.easeInOut(duration: 0.12)) {
                                                    selectedForecastWeek = week
                                                }
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.easeOut(duration: 0.3).delay(1.5)) {
                                            selectedForecastWeek = nil
                                        }
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: forecastWeekCount == 8 ? 8 : 6)) {
                        AxisValueLabel()
                            .font(.system(size: 9))
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
                .frame(height: 160)

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
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROFIT & LOSS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("This month")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                VStack(spacing: 0) {
                    plRow(
                        label: "Revenue",
                        value: monthIncome,
                        color: Color.sweeplySuccess,
                        icon: "arrow.down.circle.fill",
                        isBold: false
                    )
                    Divider().padding(.leading, 40)
                    plRow(
                        label: "Expenses",
                        value: -monthExpenses,
                        color: Color.sweeplyDestructive,
                        icon: "arrow.up.circle.fill",
                        isBold: false
                    )
                    Divider()
                    plRow(
                        label: "Net Profit",
                        value: netProfit,
                        color: netProfit >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive,
                        icon: netProfit >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        isBold: true
                    )
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))

                if priorMonthIncome > 0 {
                    let delta = monthIncome - priorMonthIncome
                    let pct = delta / priorMonthIncome
                    HStack(spacing: 6) {
                        Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.0f%% vs last month", abs(pct * 100)))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(pct >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((pct >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive).opacity(0.1))
                    .clipShape(Capsule())
                }
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

                let categories = expenseStore.byCategory(in: currentMonthInterval)
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
                            categoryRow(cat: cat, amount: amount, maxAmount: maxAmount)
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(cat: ExpenseCategory, amount: Double, maxAmount: Double) -> some View {
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
                    Text(amount.currency)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.sweeplyBorder.opacity(0.6))
                            .frame(height: 5)
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

    // MARK: - Invoice Health

    private var invoiceHealthSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("INVOICE HEALTH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)

                HStack(spacing: 10) {
                    invoiceStatBox(
                        label: "Paid",
                        count: paidInvoices.count,
                        total: paidTotal,
                        color: Color.sweeplySuccess
                    )
                    invoiceStatBox(
                        label: "Outstanding",
                        count: unpaidInvoices.count,
                        total: unpaidTotal,
                        color: Color.sweeplyWarning
                    )
                    invoiceStatBox(
                        label: "Overdue",
                        count: overdueInvoices.count,
                        total: overdueTotal,
                        color: Color.sweeplyDestructive
                    )
                }

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
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.sweeplyBorder.opacity(0.5))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.sweeplyAccent)
                                .frame(width: geo.size.width * CGFloat(collectionRate), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    private func invoiceStatBox(label: String, count: Int, total: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.sweeplyNavy)
            Text(total.currency)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
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
                            if idx < paymentMethodStats.count - 1 {
                                Divider().padding(.leading, 46)
                            }
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

    // MARK: - Top Clients

    private var topClientsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("TOP CLIENTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)

                if topClients.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2")
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        Text("No paid invoices yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(topClients.enumerated()), id: \.element.name) { idx, client in
                            topClientRow(rank: idx + 1, name: client.name, total: client.total)
                            if idx < topClients.count - 1 {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }

    private func topClientRow(rank: Int, name: String, total: Double) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rank == 1 ? Color(hue: 0.12, saturation: 0.8, brightness: 0.85).opacity(0.15)
                          : Color.sweeplyBorder.opacity(0.5))
                    .frame(width: 34, height: 34)
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rank == 1 ? Color(hue: 0.12, saturation: 0.8, brightness: 0.75)
                                     : Color.sweeplyTextSub)
            }
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
                .lineLimit(1)
            Spacer()
            Text(total.currency)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func overviewTrendBadge(trend: Double) -> some View {
        let isUp = trend >= 0
        let color: Color = isUp ? Color.sweeplySuccess : Color.sweeplyDestructive
        let icon = isUp ? "arrow.up.right" : "arrow.down.right"
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
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
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyTextSub)
        }
    }
}

// MARK: - Supporting Types (internal, accessible within module)

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
