import SwiftUI

struct InvoicesDetailListView: View {
    let status: InvoiceStatus
    let invoices: [Invoice]

    private var accentColor: Color {
        switch status {
        case .paid:    return .sweeplySuccess
        case .unpaid:  return .sweeplyWarning
        case .overdue: return .sweeplyDestructive
        }
    }

    private var navTitle: String {
        switch status {
        case .paid:    return "Paid Invoices".translated()
        case .unpaid:  return "Outstanding Invoices".translated()
        case .overdue: return "Overdue Invoices".translated()
        }
    }

    private var sortedInvoices: [Invoice] {
        switch status {
        case .paid:    return invoices.sorted { ($0.paidAt ?? $0.createdAt) > ($1.paidAt ?? $1.createdAt) }
        case .unpaid:  return invoices.sorted { $0.dueDate < $1.dueDate }
        case .overdue: return invoices.sorted { $0.dueDate < $1.dueDate }
        }
    }

    private var totalAmount: Double { invoices.reduce(0) { $0 + $1.total } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryStrip

                if sortedInvoices.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedInvoices.enumerated()), id: \.element.id) { idx, invoice in
                            InvoiceDetailRow(invoice: invoice, status: status, accentColor: accentColor)
                            if idx < sortedInvoices.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 80)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryStrip: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(invoices.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .monospacedDigit()
                Text(invoices.count == 1 ? "invoice".translated() : "invoices".translated())
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(totalAmount.currency)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("total".translated())
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private var emptyStateText: String {
        switch status {
        case .paid:    return "No paid invoices".translated()
        case .unpaid:  return "No outstanding invoices".translated()
        case .overdue: return "No overdue invoices".translated()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
            Text(emptyStateText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Row

private struct InvoiceDetailRow: View {
    let invoice: Invoice
    let status: InvoiceStatus
    let accentColor: Color

    private var daysOverdue: Int {
        max(0, Calendar.current.dateComponents([.day], from: invoice.dueDate, to: Date()).day ?? 0)
    }

    private var daysUntilDue: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: invoice.dueDate).day ?? 0)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.invoiceNumber)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)

                Text(invoice.clientName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)

                contextLine
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(invoice.total.currency)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)

                statusBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var contextLine: some View {
        switch status {
        case .overdue:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                Text(daysOverdue == 1
                     ? "%d day overdue".translated(with: daysOverdue)
                     : "%d days overdue".translated(with: daysOverdue))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.sweeplyDestructive)

        case .unpaid:
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text(daysUntilDue == 0
                     ? "Due today".translated()
                     : daysUntilDue == 1
                         ? "Due in 1 day".translated()
                         : "Due in %d days".translated(with: daysUntilDue))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.sweeplyWarning)

        case .paid:
            if let paidAt = invoice.paidAt {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Paid %@".translated(with: formatted(paidAt)))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.sweeplySuccess)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .overdue:
            Text("Overdue".translated())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.sweeplyDestructive)
                .clipShape(Capsule())

        case .unpaid:
            Text("Outstanding".translated())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sweeplyWarning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.sweeplyWarning.opacity(0.13))
                .clipShape(Capsule())

        case .paid:
            Text("Paid".translated())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sweeplySuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.sweeplySuccess.opacity(0.13))
                .clipShape(Capsule())
        }
    }
}
