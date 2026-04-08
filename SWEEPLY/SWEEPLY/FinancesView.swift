import SwiftUI
import Charts

struct FinancesView: View {
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(AppSession.self) private var session

    @State private var selectedPeriod: ChartPeriod = .week
    @State private var selectedFilter: InvoiceFilter = .all
    @State private var appeared = false
    @State private var selectedBarMonth: String? = nil

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
    }

    // MARK: - Summary

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                eyebrow: nil,
                title: "Finances",
                subtitle: invoicesStore.lastError?.isEmpty == false ? "Invoice sync issue" : "Overview"
            ) {
                HeaderIconButton(systemName: "plus", foregroundColor: .white, backgroundColor: .sweeplyNavy) {}
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

private struct MinimalInvoiceRow: View {
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

#Preview {
    FinancesView()
}
