import SwiftUI
import Charts

struct FinancesView: View {
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session
    @Environment(ExpenseStore.self) private var expenseStore

    @State private var selectedPeriod: ChartPeriod = .week
    @State private var selectedFilter: InvoiceFilter = .all
    @State private var appeared = false
    @State private var selectedBarMonth: String? = nil
    @State private var showFinanceAI = false
    @State private var showInvoicesList = false
    @State private var showExpenses = false

    private var invoices: [Invoice] {
        invoicesStore.invoices
    }

    enum ChartPeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
    }

    enum InvoiceFilter: String, CaseIterable {
        case all     = "All"
        case paid    = "Paid"
        case unpaid  = "Unpaid"
        case overdue = "Overdue"
    }

    private var totalCollected: Double {
        invoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.total }
    }
    private var totalOutstanding: Double {
        invoices.filter { $0.status == .unpaid }.reduce(0) { $0 + $1.total }
    }
    private var totalOverdue: Double {
        invoices.filter { $0.status == .overdue }.reduce(0) { $0 + $1.total }
    }
    private var collectionRate: Int {
        let total = invoices.reduce(0) { $0 + $1.total }
        guard total > 0 else { return 0 }
        return Int((totalCollected / total) * 100)
    }
    private var avgInvoiceValue: Double {
        guard !invoices.isEmpty else { return 0 }
        return invoices.reduce(0) { $0 + $1.total } / Double(invoices.count)
    }
    private var sixMonthBarData: [MonthlyBar] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<6).reversed().compactMap { offset -> MonthlyBar? in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: now),
                  let interval = calendar.dateInterval(of: .month, for: monthStart) else { return nil }
            let f = DateFormatter()
            f.dateFormat = "MMM"
            let label = f.string(from: interval.start)
            let collected = invoices.filter {
                $0.status == .paid && $0.createdAt >= interval.start && $0.createdAt < interval.end
            }.reduce(0) { $0 + $1.total }
            let pipeline = invoices.filter {
                $0.status != .paid && $0.createdAt >= interval.start && $0.createdAt < interval.end
            }.reduce(0) { $0 + $1.total }
            return MonthlyBar(month: label, collected: collected, pipeline: pipeline)
        }
    }
    private var chartData: [WeeklyRevenue] {
        selectedPeriod == .week ? weeklyChartData : monthlyChartData
    }
    private var chartMax: Double {
        max(chartData.map { $0.amount }.max() ?? 1, 1)
    }
    private var filteredInvoices: [Invoice] {
        let sorted = invoices.sorted { a, b in
            let rank: (Invoice) -> Int = {
                switch $0.status {
                case .overdue: return 0
                case .unpaid:  return 1
                case .paid:    return 2
                }
            }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.dueDate < b.dueDate
        }
        switch selectedFilter {
        case .all:     return sorted
        case .paid:    return sorted.filter { $0.status == .paid }
        case .unpaid:  return sorted.filter { $0.status == .unpaid }
        case .overdue: return sorted.filter { $0.status == .overdue }
        }
    }
    private func count(for filter: InvoiceFilter) -> Int {
        switch filter {
        case .all:     return invoices.count
        case .paid:    return invoices.filter { $0.status == .paid }.count
        case .unpaid:  return invoices.filter { $0.status == .unpaid }.count
        case .overdue: return invoices.filter { $0.status == .overdue }.count
        }
    }

    private var weeklyChartData: [WeeklyRevenue] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), end: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let amount = invoices
                .filter { invoice in
                    calendar.isDate(invoice.createdAt, inSameDayAs: date) && invoice.status == .paid
                }
                .reduce(0) { $0 + $1.total }
            return WeeklyRevenue(day: formatter.string(from: date), amount: amount)
        }
    }

    private var monthlyChartData: [WeeklyRevenue] {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), end: Date())

        return (0..<4).map { index in
            let weekStart = calendar.date(byAdding: .day, value: index * 7, to: monthInterval.start) ?? monthInterval.start
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let amount = invoices
                .filter { invoice in
                    invoice.createdAt >= weekStart && invoice.createdAt < weekEnd && invoice.status == .paid
                }
                .reduce(0) { $0 + $1.total }
            return WeeklyRevenue(day: "W\(index + 1)", amount: amount)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                summaryBlock
                chartSection
                secondaryMetrics
                expenseSummarySection
                sixMonthChartSection
                invoicesBlock
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { appeared = true }
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .refreshable {
            await invoicesStore.load(isAuthenticated: session.isAuthenticated)
        }
        .sheet(isPresented: $showFinanceAI) {
            AIChatView(financeMode: true)
                .environment(jobsStore)
                .environment(clientsStore)
                .environment(invoicesStore)
                .environment(profileStore)
        }
        .sheet(isPresented: $showInvoicesList) {
            InvoicesListView()
                .environment(invoicesStore)
                .environment(clientsStore)
                .environment(session)
                .environment(profileStore)
        }
        .sheet(isPresented: $showExpenses) {
            ExpensesView()
                .environment(expenseStore)
                .environment(session)
        }
    }

    // MARK: - Summary

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                eyebrow: nil,
                title: "Finances",
                subtitle: invoicesStore.lastError?.isEmpty == false ? "Invoice sync issue" : "Overview"
            ) {
                Menu {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showInvoicesList = true
                    } label: {
                        Label("Invoices", systemImage: "doc.text.fill")
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showExpenses = true
                    } label: {
                        Label("Expenses", systemImage: "creditcard.fill")
                    }
                    Divider()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showFinanceAI = true
                    } label: {
                        Label("Finance AI", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 40, height: 40)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                }
            }
            .padding(.top, 8)

            if let error = invoicesStore.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyDestructive)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(totalCollected.currency)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .monospacedDigit()
                    }

                    Divider()

                    HStack(spacing: 24) {
                        minimalStatColumn(title: "Outstanding", value: totalOutstanding.currency)
                        minimalStatColumn(title: "Overdue", value: totalOverdue.currency)
                    }
                }
            }
        }
    }

    private func minimalStatColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.sweeplyNavy)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var chartSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Cash flow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Spacer()
                    Picker("", selection: $selectedPeriod) {
                        ForEach(ChartPeriod.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }

                BarChartView(data: chartData, maxValue: chartMax)
                    .frame(height: 120)
                    .animation(.easeInOut(duration: 0.25), value: selectedPeriod)
            }
        }
    }

    // MARK: - Secondary metrics

    private var secondaryMetrics: some View {
        SectionCard {
            HStack(spacing: 0) {
                compactMetric(title: "Avg. invoice", value: avgInvoiceValue.currency)
                divider
                compactMetric(title: "Collection", value: "\(collectionRate)%")
                divider
                compactMetric(title: "Invoices", value: "\(invoices.count)", isCount: true)
            }
            .padding(.vertical, 0)
            .padding(.horizontal, 0)
        }
    }

    // MARK: - Expense Summary

    private var currentMonthInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.dateInterval(of: .month, for: now) else {
            return DateInterval(start: now, duration: 0)
        }
        return start
    }

    private var monthExpenseTotal: Double {
        expenseStore.total(in: currentMonthInterval)
    }

    private var monthCollected: Double {
        let interval = currentMonthInterval
        return invoices
            .filter { $0.status == .paid && interval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }

    private var netProfit: Double { monthCollected - monthExpenseTotal }

    private var expenseSummarySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Month")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("Profit & Expenses")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showExpenses = true
                    } label: {
                        Text("Add Expense")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.sweeplyNavy.opacity(0.07))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                HStack(spacing: 0) {
                    profitCell(
                        title: "Revenue",
                        value: monthCollected.currency,
                        color: Color.sweeplyAccent
                    )
                    Rectangle().fill(Color.sweeplyBorder).frame(width: 1).padding(.vertical, 4)
                    profitCell(
                        title: "Expenses",
                        value: monthExpenseTotal.currency,
                        color: Color.sweeplyDestructive
                    )
                    Rectangle().fill(Color.sweeplyBorder).frame(width: 1).padding(.vertical, 4)
                    profitCell(
                        title: "Net Profit",
                        value: netProfit.currency,
                        color: netProfit >= 0 ? Color.sweeplySuccess : Color.sweeplyDestructive
                    )
                }

                // Category breakdown (only if there are expenses)
                let cats = expenseStore.byCategory(in: currentMonthInterval)
                if !cats.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(cats, id: \.0) { cat, amount in
                            HStack(spacing: 10) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .frame(width: 18)
                                Text(cat.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text(amount.currency)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyNavy)
                                // Mini bar
                                if monthExpenseTotal > 0 {
                                    Capsule()
                                        .fill(Color.sweeplyAccent.opacity(0.3))
                                        .frame(width: max(4, 50 * (amount / monthExpenseTotal)), height: 4)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func profitCell(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private func compactMetric(title: String, value: String, isCount: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: isCount ? 17 : 15, weight: .semibold, design: isCount ? .default : .rounded))
                .foregroundStyle(Color.sweeplyNavy)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 6-Month Grouped Bar Chart

    private var sixMonthChartSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("6-Month Overview")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Spacer()
                    HStack(spacing: 12) {
                        legendDot(color: Color.sweeplyAccent, label: "Collected")
                        legendDot(color: Color.sweeplyNavy.opacity(0.25), label: "Pipeline")
                    }
                }

                Chart(sixMonthBarData) { bar in
                    BarMark(
                        x: .value("Month", bar.month),
                        y: .value("Amount", bar.collected),
                        width: .ratio(0.38)
                    )
                    .foregroundStyle(Color.sweeplyAccent)
                    .cornerRadius(3)
                    .offset(x: -8)

                    BarMark(
                        x: .value("Month", bar.month),
                        y: .value("Amount", bar.pipeline),
                        width: .ratio(0.38)
                    )
                    .foregroundStyle(Color.sweeplyNavy.opacity(0.25))
                    .cornerRadius(3)
                    .offset(x: 8)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.sweeplyBorder)
                        AxisValueLabel {
                            if let d = val.as(Double.self) {
                                Text(d.shortCurrency)
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 140)
                .animation(.easeOut(duration: 0.5), value: appeared)

                if let month = selectedBarMonth,
                   let bar = sixMonthBarData.first(where: { $0.month == month }) {
                    HStack {
                        Text(month)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text("Collected: \(bar.collected.currency)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.sweeplyAccent)
                        Text("·")
                            .foregroundStyle(Color.sweeplyBorder)
                        Text("Pipeline: \(bar.pipeline.currency)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
    }

    // MARK: - Invoices

    private var invoicesBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Invoices")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                if selectedFilter != .all {
                    Text("\(filteredInvoices.count) shown")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(InvoiceFilter.allCases, id: \.self) { filter in
                        filterTab(filter)
                    }
                }
            }

            if filteredInvoices.isEmpty {
                emptyState
            } else {
                SectionCard {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredInvoices.enumerated()), id: \.element.id) { idx, invoice in
                            MinimalInvoiceRow(invoice: invoice, invoicesStore: invoicesStore)
                            if idx < filteredInvoices.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(-16) // full bleed in SectionCard
                }
            }
        }
    }

    private func filterTab(_ filter: InvoiceFilter) -> some View {
        let selected = selectedFilter == filter
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = filter }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Text("\(count(for: filter))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .monospacedDigit()
                }
                .foregroundStyle(selected ? Color.sweeplyNavy : Color.sweeplyTextSub)
                Rectangle()
                    .fill(selected ? Color.sweeplyAccent : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: selectedFilter == .all ? "doc.text.fill" : "line.3.horizontal.decrease.circle",
            title: selectedFilter == .all ? "No invoices yet" : "No \(selectedFilter.rawValue.lowercased()) invoices",
            subtitle: selectedFilter == .all
                ? "Your first invoice will appear here once created."
                : "Try a different filter to see more invoices."
        )
    }
}

// MARK: - Models

private struct MonthlyBar: Identifiable {
    var id: String { month }
    let month: String
    let collected: Double
    let pipeline: Double
}

private extension Double {
    var shortCurrency: String {
        if self >= 1000 { return "$\(String(format: "%.1f", self / 1000))k" }
        return "$\(Int(self))"
    }
}

// MARK: - Bar chart (monochrome)

private struct BarChartView: View {
    let data: [WeeklyRevenue]
    let maxValue: Double

    private let barColor = Color.sweeplyNavy.opacity(0.78)
    private let emptyBar = Color.sweeplyBorder.opacity(0.85)

    var body: some View {
        GeometryReader { geo in
            let labelHeight: CGFloat = 16
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data) { entry in
                    let barHeight = entry.amount > 0
                        ? max(4, CGFloat(entry.amount / maxValue) * (geo.size.height - labelHeight - 6))
                        : 3
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(entry.amount > 0 ? barColor : emptyBar)
                            .frame(height: barHeight)
                        Text(entry.day)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(height: labelHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Invoice row

struct MinimalInvoiceRow: View {
    let invoice: Invoice
    let invoicesStore: InvoicesStore

    private var dueDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let ds = f.string(from: invoice.dueDate)
        switch invoice.status {
        case .paid:    return "Paid \(ds)"
        case .unpaid:  return "Due \(ds)"
        case .overdue: return "Overdue since \(ds)"
        }
    }

    private var dueDateColor: Color {
        invoice.status == .overdue ? Color.sweeplyDestructive : Color.sweeplyTextSub
    }

    var body: some View {
        NavigationLink(destination: InvoiceDetailView(invoiceId: invoice.id)) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(invoice.clientName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(invoice.total.currency)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text(invoice.invoiceNumber)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("·")
                            .foregroundStyle(Color.sweeplyBorder)
                        Text(dueDateLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(dueDateColor)
                        Spacer(minLength: 8)
                        InvoiceStatusBadge(status: invoice.status)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyBorder)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if invoice.status != .paid {
                Button { Task { await invoicesStore.markPaid(id: invoice.id) } } label: {
                    Label("Mark as paid", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                Task { await invoicesStore.delete(id: invoice.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Invoices List View

struct InvoicesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self) private var session
    @Environment(ProfileStore.self) private var profileStore

    @State private var selectedFilter: InvoiceFilter = .all
    @State private var searchText = ""

    private enum InvoiceFilter: String, CaseIterable {
        case all = "All"
        case unpaid = "Unpaid"
        case overdue = "Overdue"
        case paid = "Paid"
    }

    private var filtered: [Invoice] {
        let base: [Invoice]
        switch selectedFilter {
        case .all:     base = invoicesStore.invoices
        case .unpaid:  base = invoicesStore.invoices.filter { $0.status == .unpaid }
        case .overdue: base = invoicesStore.invoices.filter { $0.status == .overdue }
        case .paid:    base = invoicesStore.invoices.filter { $0.status == .paid }
        }
        if searchText.isEmpty { return base.sorted { a, b in statusRank(a) < statusRank(b) } }
        return base.filter {
            $0.clientName.localizedCaseInsensitiveContains(searchText) ||
            $0.invoiceNumber.localizedCaseInsensitiveContains(searchText)
        }.sorted { a, b in statusRank(a) < statusRank(b) }
    }

    private func statusRank(_ i: Invoice) -> Int {
        switch i.status { case .overdue: return 0; case .unpaid: return 1; case .paid: return 2 }
    }

    private func count(for filter: InvoiceFilter) -> Int {
        switch filter {
        case .all:     return invoicesStore.invoices.count
        case .unpaid:  return invoicesStore.invoices.filter { $0.status == .unpaid }.count
        case .overdue: return invoicesStore.invoices.filter { $0.status == .overdue }.count
        case .paid:    return invoicesStore.invoices.filter { $0.status == .paid }.count
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary strip
                    summaryStrip

                    // Filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(InvoiceFilter.allCases, id: \.self) { filter in
                                filterPill(filter)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)

                    // List
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: selectedFilter == .all ? "doc.text" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
                            Text(selectedFilter == .all ? "No invoices yet" : "No \(selectedFilter.rawValue.lowercased()) invoices")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, invoice in
                                MinimalInvoiceRow(invoice: invoice, invoicesStore: invoicesStore)
                                if idx < filtered.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search invoices…")
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Invoices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(
                label: "Outstanding",
                value: invoicesStore.invoices.filter { $0.status == .unpaid }.reduce(0) { $0 + $1.total }.currency,
                color: .sweeplyWarning
            )
            Divider().padding(.vertical, 10)
            summaryCell(
                label: "Overdue",
                value: invoicesStore.invoices.filter { $0.status == .overdue }.reduce(0) { $0 + $1.total }.currency,
                color: .sweeplyDestructive
            )
            Divider().padding(.vertical, 10)
            summaryCell(
                label: "Collected",
                value: invoicesStore.invoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.total }.currency,
                color: .sweeplySuccess
            )
        }
        .padding(.vertical, 12)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
        .padding(.top, 8)
    }

    private func summaryCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
    }

    private func filterPill(_ filter: InvoiceFilter) -> some View {
        let selected = selectedFilter == filter
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter }
        } label: {
            HStack(spacing: 5) {
                Text(filter.rawValue)
                    .font(.system(size: 13, weight: selected ? .bold : .medium))
                Text("\(count(for: filter))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? .white : Color.sweeplyNavy)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Color.sweeplyNavy : Color.sweeplySurface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Color.sweeplyBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FinancesView()
}
