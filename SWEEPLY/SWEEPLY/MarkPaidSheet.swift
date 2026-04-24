import SwiftUI

struct MarkPaidSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    
    let invoice: Invoice
    @State private var selectedMethod: PaymentMethod = .cash
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(invoice.clientName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text(invoice.invoiceNumber)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(invoice.total.currency)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyAccent)
                            .padding(.top, 4)
                    }
                    .padding(.top, 8)

                    SectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Payment Method")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(PaymentMethod.allCases, id: \.self) { method in
                                    paymentMethodButton(method)
                                }
                            }
                        }
                    }

                    Spacer()

                    Button {
                        Task { await confirmPayment() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            } else {
                                Label("Mark as Paid", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.sweeplySuccess)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
    
    private func paymentMethodButton(_ method: PaymentMethod) -> some View {
        let selected = selectedMethod == method
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.1)) { selectedMethod = method }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: method.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? .white : Color.sweeplyAccent)
                Text(method.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? .white : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                selected ? Color.sweeplyNavy : Color.sweeplyBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @MainActor
    private func confirmPayment() async {
        isSaving = true
        defer { isSaving = false }
        
        let success = await invoicesStore.markPaid(
            id: invoice.id,
            amount: invoice.total,
            method: selectedMethod
        )
        
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}