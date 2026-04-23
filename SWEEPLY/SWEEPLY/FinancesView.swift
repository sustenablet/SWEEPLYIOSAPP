import SwiftUI
import Charts

struct FinancesView: View {
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session
    @Environment(ExpenseStore.self) private var expenseStore
    @Environment(TeamStore.self)    private var teamStore

    @AppStorage("financesChartPeriod")   private var selectedPeriodRaw: String = ChartPeriod.week.rawValue
    @AppStorage("financesInvoiceFilter") private var selectedFilterRaw: String = InvoiceFilter.all.rawValue

    private var selectedPeriod: ChartPeriod { ChartPeriod(rawValue: selectedPeriodRaw) ?? .week }
    private var selectedPeriodBinding: Binding<ChartPeriod> {
        Binding(get: { ChartPeriod(rawValue: selectedPeriodRaw) ?? .week }, set: { selectedPeriodRaw = $0.rawValue })
    }
    private var selectedFilter: InvoiceFilter { InvoiceFilter(rawValue: selectedFilterRaw) ?? .all }
    @State private var appeared = false
    @State private var selectedBarMonth: String? = nil
    @State private var showFinanceAI = false
    @State private var showInvoicesList = false
    @State private var showExpenses = false
    @State private var showNewInvoice = false

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
                teamPayrollSection
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
            AIChatView(
                onNewInvoice: { showFinanceAI = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showNewInvoice = true } },
                financeMode: true
            )
            .environment(jobsStore)
            .environment(clientsStore)
            .environment(invoicesStore)
            .environment(profileStore)
            .environment(teamStore)
        }
        .sheet(isPresented: $showInvoicesList) {
            InvoicesListView()
                .environment(invoicesStore)
                .environment(clientsStore)
                .environment(jobsStore)
                .environment(session)
                .environment(profileStore)
        }
        .sheet(isPresented: $showNewInvoice) {
            NewInvoiceView()
                .environment(invoicesStore)
                .environment(clientsStore)
                .environment(jobsStore)
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
                    Picker("", selection: selectedPeriodBinding) {
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

                // Expense list with swipe-to-delete
                let monthExpenses = expenseStore.expenses
                    .filter { currentMonthInterval.contains($0.date) }
                    .sorted { $0.date > $1.date }
                if !monthExpenses.isEmpty {
                    Divider()
                    
                    HStack {
                        Text("Expenses")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Spacer()
                        Text("\(monthExpenses.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    
                    VStack(spacing: 0) {
                        ForEach(Array(monthExpenses.enumerated()), id: \.element.id) { idx, expense in
                            expenseListRow(expense)
                            if idx < monthExpenses.count - 1 {
                                Divider().padding(.leading, 58)
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
    
    private func expenseListRow(_ expense: Expense) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(expenseCategoryColor(expense.category).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: expense.category.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(expenseCategoryColor(expense.category))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(expense.category.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            
            Spacer()
            
            Text("−\(expense.amount.currency)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyDestructive)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await expenseStore.remove(id: expense.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func expenseCategoryColor(_ cat: ExpenseCategory) -> Color {
        switch cat {
        case .supplies:    return Color(hue: 0.58, saturation: 0.70, brightness: 0.75)
        case .fuel:        return Color(hue: 0.08, saturation: 0.80, brightness: 0.82)
        case .equipment:   return Color(hue: 0.55, saturation: 0.60, brightness: 0.65)
        case .insurance:   return Color(hue: 0.35, saturation: 0.65, brightness: 0.68)
        case .marketing:   return Color(hue: 0.78, saturation: 0.55, brightness: 0.75)
        case .other:       return Color(hue: 0.40, saturation: 0.45, brightness: 0.60)
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
            withAnimation(.easeInOut(duration: 0.2)) { selectedFilterRaw = filter.rawValue }
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

    // MARK: - Team Payroll

    @State private var showPaymentSheet = false
    @State private var selectedPaymentMember: TeamMember?
    @State private var paymentAmount = ""
    @State private var paymentNotes = ""

    private var teamPayrollSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Team Payroll", subtitle: "This month's earnings", action: nil)

                if teamStore.members.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                        Text("No team members yet")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(teamStore.members.enumerated()), id: \.element.id) { index, member in
                            payrollRow(member: member)
                            if index < teamStore.members.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPaymentSheet) {
            if let member = selectedPaymentMember {
                PaymentSheet(
                    member: member,
                    amount: $paymentAmount,
                    notes: $paymentNotes,
                    onPay: { Task {
                        let ok = await processPayment(member: member)
                        if ok {
                            showPaymentSheet = false
                            paymentAmount = ""
                            paymentNotes = ""
                        }
                    }}
                )
            }
        }
    }

    private func payrollRow(member: TeamMember) -> some View {
        let jobs = completedJobsThisMonth(for: member)
        let grossAmount = earnedThisMonth(for: member)
        let rateAmount = calculateEarningsWithRate(for: member)
        let nameInitials = member.name.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
        let initStr = String(nameInitials.prefix(2))

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 36, height: 36)
                Text(initStr.isEmpty ? "?" : initStr)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                if member.payRateEnabled && member.payRateAmount > 0 {
                    Text(member.payRateDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyAccent)
                } else {
                    Text("Rate not set")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if member.payRateEnabled && member.payRateAmount > 0 && grossAmount > rateAmount {
                    HStack(spacing: 4) {
                        Text(rateAmount.currency)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                        Text(grossAmount.currency)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                } else {
                    Text(grossAmount.currency)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Text("\(jobs.count) job\(jobs.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Button {
                selectedPaymentMember = member
                paymentAmount = "\(Int(rateAmount))"
                showPaymentSheet = true
            } label: {
                Text("Pay")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.sweeplyNavy)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func completedJobsThisMonth(for member: TeamMember) -> [Job] {
        guard let start = Calendar.current.dateInterval(of: .month, for: Date())?.start else { return [] }
        return jobsStore.jobs.filter { job in
            job.assignedMemberId == member.id && job.status == .completed && job.date >= start
        }
    }

    private func earnedThisMonth(for member: TeamMember) -> Double {
        completedJobsThisMonth(for: member).reduce(0.0) { $0 + $1.price }
    }

    private func calculateEarningsWithRate(for member: TeamMember) -> Double {
        guard member.payRateEnabled && member.payRateAmount > 0 else {
            return earnedThisMonth(for: member)
        }

        let jobs = completedJobsThisMonth(for: member)
        let cal = Calendar.current

        switch member.payRateType {
        case .perJob:
            return Double(jobs.count) * member.payRateAmount
        case .perDay:
            let dailyTotals = Dictionary(grouping: jobs) { job in
                cal.startOfDay(for: job.date)
            }
            return dailyTotals.values.reduce(0.0) { acc, _ in acc + member.payRateAmount }
        case .perWeek:
            return member.payRateAmount
        case .custom:
            return member.payRateAmount
        }
    }

    private func processPayment(member: TeamMember) async -> Bool {
        guard let amount = Double(paymentAmount), amount > 0,
              let ownerId = session.userId else { return false }

        let payment = TeamPayment(
            memberId: member.id,
            ownerId: ownerId,
            amount: amount,
            notes: paymentNotes
        )

        var store = TeamPaymentsStore()
        return await store.add(payment)
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
                Button { Task { await invoicesStore.markPaid(id: invoice.id, amount: invoice.total, method: .cash) } } label: {
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
    @Environment(JobsStore.self) private var jobsStore
    @Environment(AppSession.self) private var session
    @Environment(ProfileStore.self) private var profileStore

    @State private var showNewInvoice = false
    @State private var selectedFilter: InvoiceFilter
    @State private var searchText = ""

    init(preselectedFilter: String = "all") {
        _selectedFilter = State(initialValue: InvoiceFilter(rawValue: preselectedFilter) ?? .all)
    }

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showNewInvoice = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.sweeplyNavy)
                }
            }
            .sheet(isPresented: $showNewInvoice) {
                NewInvoiceView()
                    .environment(invoicesStore)
                    .environment(clientsStore)
                    .environment(jobsStore)
                    .environment(session)
                    .environment(profileStore)
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

// MARK: - Payment Sheet

private struct PaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let member: TeamMember
    @Binding var amount: String
    @Binding var notes: String
    let onPay: () -> Void

    @State private var isPaying = false

    private var parsedAmount: Double? {
        let cleaned = amount.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private var canPay: Bool {
        (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Payment Amount")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        
                        HStack {
                            Text("$")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            
                            TextField("0", text: $amount)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .keyboardType(.decimalPad)
                        }
                        .padding(16)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes (optional)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        
                        TextField("Payment for this week...", text: $notes, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(3)
                            .padding(12)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer()

                    Button {
                        isPaying = true
                        onPay()
                    } label: {
                        HStack {
                            if isPaying {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Record Payment")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canPay ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canPay || isPaying)
                }
                .padding(20)
            }
            .navigationTitle("Pay \(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
}

#Preview {
    FinancesView()
}
