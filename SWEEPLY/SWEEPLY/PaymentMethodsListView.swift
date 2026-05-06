import SwiftUI

struct PaymentMethodsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    
    @State private var selectedTab: PaymentMethod? = nil
    
    private var paidInvoices: [Invoice] {
        invoicesStore.invoices.filter { $0.status == .paid && $0.paymentMethod != nil }
    }
    
    private var paymentMethodInvoices: [PaymentMethod: [Invoice]] {
        Dictionary(grouping: paidInvoices) { $0.paymentMethod ?? .other }
    }
    
    private var tabs: [(method: PaymentMethod?, label: String)] {
        var result: [(method: PaymentMethod?, label: String)] = [(nil, "All")]
        for method in PaymentMethod.allCases {
            if paymentMethodInvoices[method] != nil {
                result.append((method, method.rawValue))
            }
        }
        return result
    }
    
    private var filteredInvoices: [Invoice] {
        if let method = selectedTab {
            return paidInvoices.filter { $0.paymentMethod == method }
        }
        return paidInvoices
    }
    
    private var totalByMethod: [PaymentMethod: Double] {
        var result: [PaymentMethod: Double] = [:]
        for (method, invoices) in paymentMethodInvoices {
            result[method] = invoices.reduce(0) { $0 + $1.total }
        }
        return result
    }
    
    private var grandTotal: Double {
        paidInvoices.reduce(0) { $0 + $1.total }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard
                tabsSection
                invoicesListSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sweeplyBackground)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Payment Methods")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL RECEIVED".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text(grandTotal.currency)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.sweeplySuccess.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.sweeplySuccess)
                }
            }
            
            Divider()
            
            HStack(spacing: 16) {
                ForEach(PaymentMethod.allCases.filter { paymentMethodInvoices[$0] != nil }, id: \.self) { method in
                    VStack(spacing: 4) {
                        Image(systemName: method.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyAccent)
                        Text(method.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text((totalByMethod[method] ?? 0).currency)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
    
    private var tabsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.label) { tab in
                    TabButton(
                        title: tab.label,
                        isSelected: selectedTab == tab.method
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab.method
                        }
                    }
                }
            }
        }
    }
    
    private var invoicesListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INVOICES".translated())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)
                Spacer()
                Text("\(filteredInvoices.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            
            if filteredInvoices.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text("No invoices found".translated())
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredInvoices.sorted(by: { ($0.paidAt ?? .distantPast) > ($1.paidAt ?? .distantPast) })) { invoice in
                        invoiceRow(invoice)
                        Divider().padding(.leading, 46)
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
    }
    
    private func invoiceRow(_ invoice: Invoice) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: invoice.paymentMethod?.icon ?? "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.clientName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
                if let date = invoice.paidAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            
            Spacer()
            
            Text(invoice.total.currency)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.sweeplyNavy : Color.sweeplySurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: isSelected ? 0 : 1))
        }
    }
}