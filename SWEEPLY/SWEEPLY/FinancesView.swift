import SwiftUI

struct FinancesView: View {
    @State private var invoices: [Invoice] = MockData.makeAllInvoices()
    @State private var selectedPeriod: ChartPeriod = .week
    @State private var selectedFilter: InvoiceFilter = .all
    @State private var appeared = false

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

    // MARK: - Computed

    private var totalCollected: Double {
        invoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
    }
    private var totalOutstanding: Double {
        invoices.filter { $0.status == .unpaid }.reduce(0) { $0 + $1.amount }
    }
    private var totalOverdue: Double {
        invoices.filter { $0.status == .overdue }.reduce(0) { $0 + $1.amount }
    }
    private var collectionRate: Int {
        let total = invoices.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return 0 }
        return Int((totalCollected / total) * 100)
    }
    private var avgInvoiceValue: Double {
        guard !invoices.isEmpty else { return 0 }
        return invoices.reduce(0) { $0 + $1.amount } / Double(invoices.count)
    }
    private var chartData: [WeeklyRevenue] {
        selectedPeriod == .week ? MockData.weeklyRevenue : MockData.monthlyRevenue
    }
    private var chartMax: Double {
        chartData.map { $0.amount }.max() ?? 1
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

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                kpiStrip
                revenueChartCard
                financialSummaryRow
                invoicesSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Finances")
                    .font(Font.custom("BricolageGrotesque-Bold", size: 22))
                    .foregroundStyle(Color.primary)
                Text("Revenue, invoices & payment tracking")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Invoice")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.sweeplyNavy)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.sweeplyAccent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    // MARK: - KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: 10) {
            FinanceKPITile(
                label: "Collected",
                value: totalCollected.currency,
                accent: Color.sweeplySuccess,
                icon: "checkmark.circle.fill"
            )
            FinanceKPITile(
                label: "Outstanding",
                value: totalOutstanding.currency,
                accent: Color.sweeplyWarning,
                icon: "clock.fill"
            )
            FinanceKPITile(
                label: "Overdue",
                value: totalOverdue.currency,
                accent: Color.sweeplyDestructive,
                icon: "exclamationmark.circle.fill"
            )
        }
    }

    // MARK: - Revenue Chart Card

    private var revenueChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revenue")
                        .font(.system(size: 15, weight: .semibold))
                    Text(totalCollected.currency + " collected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()
                HStack(spacing: 0) {
                    ForEach(ChartPeriod.allCases, id: \.self) { period in
                        Button(period.rawValue) {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedPeriod = period }
                        }
                        .font(.system(size: 11, weight: selectedPeriod == period ? .semibold : .medium))
                        .foregroundStyle(selectedPeriod == period ? Color.sweeplyNavy : Color.sweeplyTextSub)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(selectedPeriod == period ? Color.sweeplyAccent : Color.clear)
                        .clipShape(Capsule())
                    }
                }
                .padding(3)
                .background(Color.sweeplyBackground)
                .clipShape(Capsule())
            }

            BarChartView(data: chartData, maxValue: chartMax)
                .frame(height: 110)
                .animation(.easeInOut(duration: 0.3), value: selectedPeriod)
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Financial Summary Row

    private var financialSummaryRow: some View {
        HStack(spacing: 10) {
            FinSummaryTile(label: "Avg Invoice", value: avgInvoiceValue.currency, mono: true)
            FinSummaryTile(label: "Collection Rate", value: "\(collectionRate)%", mono: true)
            FinSummaryTile(label: "Total Invoices", value: "\(invoices.count)", mono: false)
        }
    }

    // MARK: - Invoices Section

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Invoices")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if selectedFilter != .all {
                    Text("\(filteredInvoices.count) of \(invoices.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvoiceFilter.allCases, id: \.self) { filter in
                        InvoiceFilterChip(
                            label: filter.rawValue,
                            count: count(for: filter),
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            if filteredInvoices.isEmpty {
                emptyInvoicesState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredInvoices.enumerated()), id: \.element.id) { idx, invoice in
                        FullInvoiceRow(invoice: invoice, invoices: $invoices)
                        if idx < filteredInvoices.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
    }

    private var emptyInvoicesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
            Text("No invoices here")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Create an invoice to start tracking your payments")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

// MARK: - KPI Tile

private struct FinanceKPITile: View {
    let label: String
    let value: String
    let accent: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Summary Tile

private struct FinSummaryTile: View {
    let label: String
    let value: String
    let mono: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: mono ? .monospaced : .default))
                .foregroundStyle(Color.sweeplyAccent)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Filter Chip

private struct InvoiceFilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy.opacity(0.6) : Color.sweeplyTextSub.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        isSelected
                        ? Color.sweeplyNavy.opacity(0.1)
                        : Color.sweeplyBorder.opacity(0.6)
                    )
                    .clipShape(Capsule())
            }
            .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyTextSub)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.sweeplyAccent : Color.sweeplySurface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bar Chart

private struct BarChartView: View {
    let data: [WeeklyRevenue]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data) { entry in
                    let barHeight = entry.amount > 0
                        ? max(6, CGFloat(entry.amount / maxValue) * (geo.size.height - 20))
                        : 4
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    entry.amount > 0
                                    ? LinearGradient(
                                        colors: [Color.sweeplyAccent, Color.sweeplyAccent.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                      )
                                    : LinearGradient(
                                        colors: [Color.sweeplyBorder.opacity(0.4), Color.sweeplyBorder.opacity(0.4)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                      )
                                )
                                .frame(height: barHeight)
                        }
                        Text(entry.day)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(height: 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Full Invoice Row

private struct FullInvoiceRow: View {
    let invoice: Invoice
    @Binding var invoices: [Invoice]

    private var statusAccent: Color {
        switch invoice.status {
        case .paid:    return Color.sweeplySuccess
        case .unpaid:  return Color.sweeplyWarning
        case .overdue: return Color.sweeplyDestructive
        }
    }

    private var dueDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let ds = f.string(from: invoice.dueDate)
        switch invoice.status {
        case .paid:    return "Paid \(ds)"
        case .unpaid:  return "Due \(ds)"
        case .overdue: return "Overdue · \(ds)"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(statusAccent)
                .frame(width: 3, height: 42)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(invoice.clientName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(invoice.amount.currency)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                }
                HStack(spacing: 6) {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyBorder)
                    Text(dueDateLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            invoice.status == .overdue
                            ? Color.sweeplyDestructive
                            : Color.sweeplyTextSub
                        )
                    Spacer()
                    InvoiceStatusBadge(status: invoice.status)
                }
            }

            // Action menu
            Menu {
                if invoice.status != .paid {
                    Button { markPaid() } label: {
                        Label("Mark as Paid", systemImage: "checkmark.circle.fill")
                    }
                    Button {} label: {
                        Label("Send Reminder", systemImage: "bell.fill")
                    }
                    Divider()
                }
                Button {} label: {
                    Label("View Details", systemImage: "doc.text")
                }
                Button(role: .destructive) {} label: {
                    Label("Delete Invoice", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 28, height: 28)
                    .background(Color.sweeplyBackground)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func markPaid() {
        if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                invoices[idx].status = .paid
            }
        }
    }
}

#Preview {
    FinancesView()
}
