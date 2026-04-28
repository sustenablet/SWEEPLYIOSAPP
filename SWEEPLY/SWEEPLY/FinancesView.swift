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

    @AppStorage("financesChartPeriod")    private var selectedPeriodRaw: String = ChartPeriod.week.rawValue
    @AppStorage("financesInvoiceFilter")  private var selectedFilterRaw: String = InvoiceFilter.all.rawValue
    @AppStorage("financesOverviewPeriod") private var overviewPeriodRaw: String = OverviewPeriod.sixMonth.rawValue

    private var selectedPeriod: ChartPeriod { ChartPeriod(rawValue: selectedPeriodRaw) ?? .week }
    private var selectedPeriodBinding: Binding<ChartPeriod> {
        Binding(get: { ChartPeriod(rawValue: selectedPeriodRaw) ?? .week }, set: { selectedPeriodRaw = $0.rawValue })
    }
    private var overviewPeriod: OverviewPeriod { OverviewPeriod(rawValue: overviewPeriodRaw) ?? .sixMonth }
    private var selectedFilter: InvoiceFilter { InvoiceFilter(rawValue: selectedFilterRaw) ?? .all }
    @State private var appeared = false
    @State private var selectedOverviewMonth: String? = nil
    @State private var showInvoicesList = false
    @State private var showExpenses = false
    @State private var showNewInvoice = false
    @State private var selectedInvoiceId: UUID? = nil
    @State private var showInvoiceDetail = false
    @State private var markPaidInvoice: Invoice? = nil
    
    // Interactive chart state
    @State private var selectedCashflowBar: String? = nil
    @State private var selectedCashflowValue: Double = 0

    // Remove the old showFinanceAI state

    private var invoices: [Invoice] {
        invoicesStore.invoices
    }

    enum ChartPeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
    }

    enum OverviewPeriod: String, CaseIterable {
        case threeMonth = "3M"
        case sixMonth   = "6M"
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

    private var cashflowDateInterval: DateInterval {
        let cal = Calendar.current
        switch selectedPeriod {
        case .week:
            return cal.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), duration: 604800)
        case .month:
            return cal.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), duration: 2592000)
        }
    }
    private var periodCollected: Double {
        invoices.filter { $0.status == .paid && cashflowDateInterval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }
    private var periodOutstanding: Double {
        invoices.filter { $0.status == .unpaid && cashflowDateInterval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
    }
    private var periodOverdue: Double {
        invoices.filter { $0.status == .overdue && cashflowDateInterval.contains($0.createdAt) }
            .reduce(0) { $0 + $1.total }
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
    
    // MARK: - Team Payroll Computed Properties
    
    private var totalPayrollLiability: Double {
        teamStore.members.reduce(0) { $0 + calculateEarningsWithRate(for: $1) }
    }
    
    private func paymentStatus(for member: TeamMember) -> PaymentStatus {
        let periodStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        let payments = memberPayments[member.id] ?? []
        
        let thisMonthPayments = payments.filter { $0.paidAt >= periodStart }
        let owed = calculateEarningsWithRate(for: member)
        
        if thisMonthPayments.isEmpty {
            // Check if it's pay day or past
            if let payDay = member.payDayOfWeek {
                let today = Calendar.current.component(.weekday, from: Date())
                if today >= payDay {
                    return .due
                }
            }
            return .pending
        }
        
        let paid = thisMonthPayments.reduce(0) { $0 + $1.amount }
        if paid >= owed {
            return .paid
        }
        return .partial(owed: owed, paid: paid)
    }
    
    private func lastPaymentDate(for member: TeamMember) -> Date? {
        let payments = memberPayments[member.id] ?? []
        return payments.sorted { $0.paidAt > $1.paidAt }.first?.paidAt
    }
    
    private func nextPayday(for member: TeamMember) -> String? {
        guard let payDay = member.payDayOfWeek else { return nil }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeekday = calendar.component(.weekday, from: today)
        
        var daysUntilPayday = payDay - currentWeekday
        if daysUntilPayday <= 0 { daysUntilPayday += 7 }
        
        guard let nextPayday = calendar.date(byAdding: .day, value: daysUntilPayday, to: today) else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: nextPayday)
    }
    
    enum PaymentStatus: Equatable {
        case paid
        case pending
        case due
        case partial(owed: Double, paid: Double)
        
        var displayText: String {
            switch self {
            case .paid: return "Paid".translated()
            case .pending: return "Pending".translated()
            case .due: return "Pay due".translated()
            case .partial: return "Partial".translated()
            }
        }
        
        var color: Color {
            switch self {
            case .paid: return Color.sweeplySuccess
            case .pending: return Color.sweeplyTextSub
            case .due: return Color.sweeplyDestructive
            case .partial: return Color.sweeplyWarning
            }
        }
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
            .padding(.bottom, 80)
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
        .sheet(isPresented: Binding(
            get: { markPaidInvoice != nil },
            set: { if !$0 { markPaidInvoice = nil } }
        )) {
            if let invoice = markPaidInvoice {
                MarkPaidSheet(invoice: invoice)
                    .environment(invoicesStore)
            }
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
                        Label("Invoices".translated(), systemImage: "doc.text.fill")
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showExpenses = true
                    } label: {
                        Label("Expenses".translated(), systemImage: "creditcard.fill")
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
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("Collected".translated())
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                Text(selectedPeriod == .week ? "This Week" : "This Month")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.sweeplyAccent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            Text(periodCollected.currency)
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.sweeplyNavy)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: selectedPeriodRaw)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 24) {
                        minimalStatColumn(title: "Outstanding", value: periodOutstanding.currency)
                        minimalStatColumn(title: "Overdue", value: periodOverdue.currency)
                    }
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: selectedPeriodRaw)
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
                    Text("Cash flow".translated())
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

                InteractiveBarChartView(
                    data: chartData,
                    maxValue: chartMax,
                    selectedBar: $selectedCashflowBar,
                    selectedValue: $selectedCashflowValue
                )
                .frame(height: 120)
                .animation(.easeInOut(duration: 0.25), value: selectedPeriod)
                
                if let bar = selectedCashflowBar, selectedCashflowValue > 0 {
                    HStack {
                        Text(bar)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text(selectedCashflowValue.currency)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
                        Text("This Month".translated())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("Profit & Expenses".translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showExpenses = true
                    } label: {
                        Text("Add Expense".translated())
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
                        Text("Expenses".translated())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Spacer()
                        Text("\(monthExpenses.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    
                    let displayExpenses = Array(monthExpenses.prefix(5))
                    let hasMore = monthExpenses.count > 5
                    
                    VStack(spacing: 0) {
                        ForEach(Array(displayExpenses.enumerated()), id: \.element.id) { idx, expense in
                            expenseListRow(expense)
                            if idx < displayExpenses.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                        
                        if hasMore {
                            Button {
                                showExpenses = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("View All \(monthExpenses.count) Expenses")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.sweeplyAccent)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyAccent)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
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
                Label("Delete".translated(), systemImage: "trash")
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

    // MARK: - Revenue Overview (3M / 6M Area Chart)

    private var sixMonthChartSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {

                // Header
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
                    // 3M / 6M toggle
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

                // Summary row
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

                // Area chart
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

                // Selected month callout
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

                // Legend
                HStack(spacing: 16) {
                    legendItem(color: Color.sweeplyAccent, label: "Collected")
                    legendItem(color: Color.sweeplyNavy.opacity(0.3), label: "Outstanding")
                }
            }
        }
    }

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

    // MARK: - Invoices

    private var displayInvoices: [Invoice] {
        Array(filteredInvoices.prefix(5))
    }

    private var hasMoreInvoices: Bool {
        filteredInvoices.count > 5
    }

    private var invoicesBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Invoices".translated())
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
                        ForEach(Array(displayInvoices.enumerated()), id: \.element.id) { idx, invoice in
                            MinimalInvoiceRow(invoice: invoice, invoicesStore: invoicesStore) {
                                selectedInvoiceId = invoice.id
                                showInvoiceDetail = true
                            }
                            if idx < displayInvoices.count - 1 {
                                Divider()
                            }
                        }

                        if hasMoreInvoices {
                            Divider()
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showInvoicesList = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("View All \(filteredInvoices.count) Invoices")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sweeplyAccent)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyAccent)
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(-16)
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
    
    // Track payments per member
    @State private var memberPayments: [UUID: [TeamPayment]] = [:]
    
    private var teamPayrollSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                // Header with summary
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Team Payroll".translated())
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                            Text("This month".translated())
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(totalPayrollLiability.currency)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                            Text("\(teamStore.members.count) member\(teamStore.members.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                }

                Divider()

                if teamStore.members.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                        Text("No team members yet".translated())
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
        let status = paymentStatus(for: member)
        let lastPaid = lastPaymentDate(for: member)
        let nextPay = nextPayday(for: member)

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy)
                        .frame(width: 36, height: 36)
                    Text(initStr.isEmpty ? "?" : initStr)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        statusBadge(for: status)
                    }
                    if member.payRateEnabled && member.payRateAmount > 0 {
                        Text(member.payRateDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyAccent)
                    } else {
                        Text("Rate not set".translated())
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
                        Text(rateAmount.currency)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    Text("\(jobs.count) job\(jobs.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                payButton(for: member, status: status, rateAmount: rateAmount)
            }

            if status == .due || (status != .paid && status != .pending) {
                HStack(spacing: 8) {
                    if status == .due {
                        Label("Payment due".translated(), systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyDestructive)
                    }
                    if let next = nextPay {
                        Label(next, systemImage: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    if let last = lastPaid {
                        Label(formatLastPaid(last), systemImage: "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplySuccess)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 12)
    }

    private func statusBadge(for status: PaymentStatus) -> some View {
        Text(status.displayText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color)
            .clipShape(Capsule())
    }

private func payButton(for member: TeamMember, status: PaymentStatus, rateAmount: Double) -> some View {
        Button {
            selectedPaymentMember = member
            paymentAmount = "\(Int(rateAmount))"
            showPaymentSheet = true
        } label: {
            HStack(spacing: 4) {
                if status == .due {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text("Pay".translated())
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(status == .due ? Color.sweeplyDestructive : Color.sweeplyNavy)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func formatLastPaid(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "Last paid MMM d"
        return formatter.string(from: date)
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
    let scheduled: Double
    var total: Double { collected + scheduled }
  }
  
  private extension Double {
    var shortCurrency: String {
      if self >= 1000 { return "$\(String(format: "%.1f", self / 1000))k" }
      return "$\(Int(self))"
    }
  }
  
  // MARK: - Interactive Bar chart (cashflow)
  
  private struct InteractiveBarChartView: View {
    let data: [WeeklyRevenue]
    let maxValue: Double
    @Binding var selectedBar: String?
    @Binding var selectedValue: Double
    
    private let barColor = Color.sweeplyNavy.opacity(0.78)
    private let selectedBarColor = Color.sweeplyAccent
    private let emptyBar = Color.sweeplyBorder.opacity(0.85)
    
    var body: some View {
      GeometryReader { geo in
        let labelHeight: CGFloat = 16
        HStack(alignment: .bottom, spacing: 8) {
          ForEach(data) { entry in
            let barHeight = entry.amount > 0
              ? max(4, CGFloat(entry.amount / maxValue) * (geo.size.height - labelHeight - 6))
              : 3
            let isSelected = selectedBar == entry.day
            
            VStack(spacing: 6) {
              Spacer(minLength: 0)
              Button {
                if entry.amount > 0 {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                      selectedBar = nil
                      selectedValue = 0
                    } else {
                      selectedBar = entry.day
                      selectedValue = entry.amount
                    }
                  }
                }
              } label: {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(isSelected ? selectedBarColor : (entry.amount > 0 ? barColor : emptyBar))
                  .frame(height: barHeight)
                  .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                      .stroke(isSelected ? Color.sweeplyAccent : Color.clear, lineWidth: 2)
                  )
              }
              .buttonStyle(.plain)
              
              Text(entry.day)
                .font(.system(size: 10, weight: selectedBar == entry.day ? .semibold : .medium))
                .foregroundStyle(selectedBar == entry.day ? Color.sweeplyNavy : Color.sweeplyTextSub)
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
    var onTap: (() -> Void)? = nil

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
                    Text("·".translated())
                        .foregroundStyle(Color.sweeplyBorder)
                    Text(dueDateLabel)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(dueDateColor)
                    Spacer(minLength: 8)
                    InvoiceStatusBadge(status: invoice.status)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
    @State private var selectedInvoiceId: UUID? = nil
    @State private var showInvoiceDetail = false
    @State private var markPaidInvoice: Invoice? = nil
    @State private var sortOrder: InvoiceSortOrder = .newestFirst

    init(preselectedFilter: String = "all") {
        _selectedFilter = State(initialValue: InvoiceFilter(rawValue: preselectedFilter) ?? .all)
    }

    private enum InvoiceFilter: String, CaseIterable {
        case all = "All"
        case unpaid = "Unpaid"
        case overdue = "Overdue"
        case paid = "Paid"
    }

    private enum InvoiceSortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case highestAmount = "Highest Amount"
        case lowestAmount = "Lowest Amount"

        var icon: String {
            switch self {
            case .newestFirst:   return "arrow.down.circle"
            case .oldestFirst:   return "arrow.up.circle"
            case .highestAmount: return "dollarsign.arrow.up"
            case .lowestAmount:  return "dollarsign.arrow.down"
            }
        }
    }

    private var hasActiveFilters: Bool {
        sortOrder != .newestFirst
    }

    private var filtered: [Invoice] {
        // Status filter
        var result: [Invoice]
        switch selectedFilter {
        case .all:     result = invoicesStore.invoices
        case .unpaid:  result = invoicesStore.invoices.filter { $0.status == .unpaid }
        case .overdue: result = invoicesStore.invoices.filter { $0.status == .overdue }
        case .paid:    result = invoicesStore.invoices.filter { $0.status == .paid }
        }

        // Search
        if !searchText.isEmpty {
            result = result.filter {
                $0.clientName.localizedCaseInsensitiveContains(searchText) ||
                $0.invoiceNumber.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort
        switch sortOrder {
        case .newestFirst:   return result.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:   return result.sorted { $0.createdAt < $1.createdAt }
        case .highestAmount: return result.sorted { $0.total > $1.total }
        case .lowestAmount:  return result.sorted { $0.total < $1.total }
        }
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

                    // Status filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(InvoiceFilter.allCases, id: \.self) { filter in
                                filterPill(filter)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)

                    // Sort filter
                    HStack(spacing: 8) {
                        Spacer()

                        // Clear filters
                        if hasActiveFilters {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation { sortOrder = .newestFirst }
                            } label: {
                                Text("Clear")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
                                MinimalInvoiceRow(invoice: invoice, invoicesStore: invoicesStore) {
                                    selectedInvoiceId = invoice.id
                                    showInvoiceDetail = true
                                }
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
            .navigationTitle("Invoices".translated())
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            ForEach(InvoiceSortOrder.allCases, id: \.self) { order in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation { sortOrder = order }
                                } label: {
                                    HStack {
                                        Text(order.rawValue)
                                        if sortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: sortOrder.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(hasActiveFilters ? Color.sweeplyAccent : Color.sweeplyTextSub)
                        }

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
            }
            .sheet(isPresented: $showNewInvoice) {
                NewInvoiceView()
                    .environment(invoicesStore)
                    .environment(clientsStore)
                    .environment(jobsStore)
                    .environment(session)
                    .environment(profileStore)
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
            .sheet(isPresented: Binding(
                get: { markPaidInvoice != nil },
                set: { if !$0 { markPaidInvoice = nil } }
            )) {
                if let invoice = markPaidInvoice {
                    MarkPaidSheet(invoice: invoice)
                        .environment(invoicesStore)
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
                        Text("Payment Amount".translated())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        
                        HStack {
                            Text("$".translated())
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
                        Text("Notes (optional)".translated())
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
                                Text("Record Payment".translated())
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
                    Button("Cancel".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
}

#Preview {
    FinancesView()
}
