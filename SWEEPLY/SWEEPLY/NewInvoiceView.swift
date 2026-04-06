import SwiftUI

struct NewInvoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self) private var session
    
    @State private var selectedClientId: UUID? = nil
    @State private var amountString: String = ""
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    
    // Using @State for invoice number to grab it on init
    @State private var autoInvoiceNumber: String = ""

    private var activeClients: [Client] {
        clientsStore.clients.filter { $0.isActive }
    }

    private var selectedClientName: String {
        return activeClients.first(where: { $0.id == selectedClientId })?.name ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        // Header
                        VStack(spacing: 8) {
                            Text("New Invoice")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            Text("Create a new invoice to collect payment.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.sweeplyDestructive)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // Form Content
                        VStack(spacing: 24) {
                            
                            // Client Selection Section
                            VStack(alignment: .leading, spacing: 16) {
                                FormSectionHeader(title: "CLIENT DETAILS")
                                
                                Menu {
                                    ForEach(activeClients) { client in
                                        Button(client.name) {
                                            selectedClientId = client.id
                                        }
                                    }
                                } label: {
                                    PickerButton(
                                        title: "Client",
                                        value: selectedClientId == nil ? "Select Client" : selectedClientName,
                                        icon: "person.fill",
                                        isValueEmpty: selectedClientId == nil
                                    )
                                }
                                
                                if activeClients.isEmpty {
                                    Text("No active clients. Add a client first.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.sweeplyDestructive)
                                        .padding(.leading, 4)
                                }
                            }
                            
                            // Invoice Details Section
                            VStack(alignment: .leading, spacing: 16) {
                                FormSectionHeader(title: "INVOICE DETAILS")
                                
                                HStack {
                                    Text("Invoice Number")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyNavy)
                                    Spacer()
                                    Text(autoInvoiceNumber)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                                .padding(16)
                                .background(Color.sweeplySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                            }
                            
                            // Payment Details
                            VStack(alignment: .leading, spacing: 16) {
                                FormSectionHeader(title: "PAYMENT")
                                
                                HStack(spacing: 16) {
                                    // Amount
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Amount")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                        HStack {
                                            Text("$")
                                                .foregroundStyle(Color.sweeplyTextSub)
                                            TextField("0.00", text: $amountString)
                                                .keyboardType(.decimalPad)
                                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        }
                                        .padding(16)
                                        .background(Color.sweeplySurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                                    }
                                    
                                    // Due Date
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Due Date")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                        
                                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                                            .labelsHidden()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.sweeplySurface)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 100) // Space for sticky footer
                }
                
                // Sticky Footer Footer
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.sweeplyBorder.opacity(0.3))
                    
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                        
                        Button {
                            createInvoice()
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Create Invoice")
                                }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 10, x: 0, y: 5)
                        }
                        .disabled(selectedClientId == nil || amountString.isEmpty || Double(amountString) == nil || isSubmitting)
                        .opacity((selectedClientId == nil || amountString.isEmpty || Double(amountString) == nil) ? 0.5 : 1.0)
                    }
                    .padding(20)
                    .background(Color.sweeplyBackground.ignoresSafeArea(edges: .bottom))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .navigationBarHidden(true)
            .onAppear {
                if autoInvoiceNumber.isEmpty {
                    autoInvoiceNumber = invoicesStore.nextInvoiceNumber()
                }
            }
        }
    }
    
    private func createInvoice() {
        guard let clientId = selectedClientId,
              let userId = session.userId,
              let amount = Double(amountString) else {
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            let clientName = activeClients.first(where: { $0.id == clientId })?.name ?? "Unknown Client"
            
            let newInvoice = Invoice(
                id: UUID(),
                clientId: clientId,
                clientName: clientName,
                amount: amount,
                status: .unpaid,
                createdAt: Date(),
                dueDate: dueDate,
                invoiceNumber: autoInvoiceNumber
            )
            
            let success = await invoicesStore.insert(newInvoice, userId: userId)
            
            await MainActor.run {
                isSubmitting = false
                if success {
                    dismiss()
                } else {
                    errorMessage = invoicesStore.lastError ?? "Failed to create invoice."
                }
            }
        }
    }
}

// MARK: - Subviews

private struct FormSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            Rectangle()
                .fill(Color.sweeplyBorder)
                .frame(height: 1)
        }
    }
}

private struct PickerButton: View {
    let title: String
    let value: String
    let icon: String
    let isValueEmpty: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyTextSub)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(isValueEmpty ? Color.sweeplyTextSub.opacity(0.6) : Color.primary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyBorder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}
