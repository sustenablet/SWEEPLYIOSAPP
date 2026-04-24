import SwiftUI

struct MarkPaidSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    
    let invoice: Invoice
    let onComplete: (() -> Void)?
    
    @State private var amount: String
    @State private var selectedMethod: PaymentMethod = .cash
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isAmountFocused: Bool
    
    private var parsedAmount: Double? {
        let cleaned = amount.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }
    
    private var canSave: Bool {
        (parsedAmount ?? 0) > 0
    }
    
    init(invoice: Invoice, onComplete: (() -> Void)? = nil) {
        self.invoice = invoice
        self.onComplete = onComplete
        _amount = State(initialValue: String(format: "%.2f", invoice.total))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Invoice info header
                    VStack(spacing: 4) {
                        Text(invoice.clientName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Invoice \(invoice.invoiceNumber)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.top, 8)
                    
                    // Amount field
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Amount Received")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("$")
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                TextField("0.00", text: $amount)
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(Color.primary)
                                    .focused($isAmountFocused)
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("Done") {
                                                isAmountFocused = false
                                            }
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyAccent)
                                        }
                                    }
                            }
                        }
                    }
                    
                    // Payment method picker
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
                    
                    // Confirm button
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
                        .background(
                            canSave ? Color.sweeplySuccess : Color.sweeplyTextSub.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || isSaving)
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
            .alert("Payment Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
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
        guard let amt = parsedAmount else { return }
        isSaving = true
        defer { isSaving = false }
        
        let success = await invoicesStore.markPaid(
            id: invoice.id,
            amount: amt,
            method: selectedMethod
        )
        
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete?()
            dismiss()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = invoicesStore.lastError ?? "Unable to record payment. Please try again."
            showError = true
        }
    }
}