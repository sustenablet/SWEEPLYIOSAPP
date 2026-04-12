import SwiftUI

struct NewInvoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session

    @State private var selectedClientId: UUID? = nil
    @State private var lineItems: [InvoiceLineItem] = []
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var autoInvoiceNumber: String = ""
    @State private var showingServicePicker = false

    init() {
        _selectedClientId = State(initialValue: nil)
        _lineItems = State(initialValue: [])
        _dueDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _notes = State(initialValue: "")
        _isSubmitting = State(initialValue: false)
        _errorMessage = State(initialValue: nil)
        _autoInvoiceNumber = State(initialValue: "")
        _showingServicePicker = State(initialValue: false)
    }

    /// Pre-fill from a completed job — client + one line item already populated.
    init(prefill: Job) {
        _selectedClientId = State(initialValue: prefill.clientId)
        _lineItems = State(initialValue: [
            InvoiceLineItem(description: prefill.serviceType.rawValue, quantity: 1, unitPrice: prefill.price)
        ])
        _dueDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _notes = State(initialValue: "")
        _isSubmitting = State(initialValue: false)
        _errorMessage = State(initialValue: nil)
        _autoInvoiceNumber = State(initialValue: "")
        _showingServicePicker = State(initialValue: false)
    }

    private var activeClients: [Client] {
        clientsStore.clients.filter { $0.isActive }
    }

    private var selectedClient: Client? {
        activeClients.first(where: { $0.id == selectedClientId })
    }

    private var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.total }
    }

    private var canSubmit: Bool {
        selectedClientId != nil && !lineItems.isEmpty && !isSubmitting
    }

    private var serviceCatalog: [BusinessService] {
        profileStore.profile?.settings.hydratedServiceCatalog ?? AppSettings.defaultServiceCatalog
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("New Invoice")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            Text(autoInvoiceNumber)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                        // Error banner
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.sweeplyDestructive)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        clientSection
                        servicesSection
                        invoiceDetailsSection
                        paymentSection
                    }
                    .padding(24)
                    .padding(.bottom, lineItems.isEmpty ? 100 : 180)
                }

                // Sticky bottom: total bar + footer
                VStack(spacing: 0) {
                    if !lineItems.isEmpty {
                        totalBar
                    }

                    Divider().background(Color.sweeplyBorder.opacity(0.3))

                    HStack(spacing: 16) {
                        Button("Cancel") { dismiss() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))

                        Button { createInvoice() } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Create Invoice")
                                }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(canSubmit ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(!canSubmit)
                    }
                    .padding(20)
                    .background(Color.sweeplyBackground.ignoresSafeArea(edges: .bottom))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .navigationBarHidden(true)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                }
            }
            .onAppear {
                if autoInvoiceNumber.isEmpty {
                    autoInvoiceNumber = invoicesStore.nextInvoiceNumber()
                }
                if activeClients.count == 1 {
                    selectedClientId = activeClients[0].id
                }
            }
            .sheet(isPresented: $showingServicePicker) {
                ServicePickerSheet(catalog: serviceCatalog) { item in
                    lineItems.append(item)
                }
            }
        }
    }

    // MARK: - CLIENT

    private var clientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InvoiceFormSectionHeader(title: "CLIENT")

            VStack(spacing: 8) {
                Menu {
                    ForEach(activeClients) { client in
                        Button(client.name) { selectedClientId = client.id }
                    }
                } label: {
                    InvoicePickerButton(
                        title: "Bill to",
                        value: selectedClient?.name ?? "Select client",
                        icon: "person.fill",
                        isValueEmpty: selectedClientId == nil
                    )
                }

                if let client = selectedClient {
                    let addressLine = [client.address, client.city, client.state]
                        .filter { !$0.isEmpty }.joined(separator: ", ")

                    if !addressLine.isEmpty || !client.email.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !addressLine.isEmpty {
                                Label(addressLine, systemImage: "mappin.and.ellipse")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            if !client.email.isEmpty {
                                Label(client.email, systemImage: "envelope")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }

                if activeClients.isEmpty {
                    Text("No active clients. Add a client first.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyDestructive)
                        .padding(.leading, 4)
                }
            }
        }
    }

    // MARK: - SERVICES

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InvoiceFormSectionHeader(title: "SERVICES")

            if lineItems.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingServicePicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.sweeplyAccent)
                        Text("Add your first service")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                Color.sweeplyAccent.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                    )
                }
            } else {
                VStack(spacing: 8) {
                    ForEach($lineItems) { $item in
                        LineItemRow(item: $item) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                lineItems.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingServicePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.sweeplyAccent)
                        Text("Add another service")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - INVOICE DETAILS

    private var invoiceDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InvoiceFormSectionHeader(title: "INVOICE DETAILS")

            VStack(spacing: 8) {
                HStack {
                    Text("Invoice No.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Spacer()
                    Text(autoInvoiceNumber)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                .padding(16)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (optional)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)

                    TextField("e.g. April monthly clean + oven detail", text: $notes, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(3...6)
                        .padding(16)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - PAYMENT

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InvoiceFormSectionHeader(title: "PAYMENT")

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)

                DatePicker("", selection: $dueDate, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))

                // Net-day preset chips
                HStack(spacing: 8) {
                    ForEach([7, 14, 7], id: \.self) { days in
                        let target = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                        let dueDateDay = Calendar.current.startOfDay(for: dueDate)
                        let isSelected = dueDateDay == target

                        Button("Net \(days)") {
                            dueDate = target
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.sweeplyNavy : Color.sweeplySurface)
                        .foregroundStyle(isSelected ? .white : Color.sweeplyTextSub)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.sweeplyBorder, lineWidth: 1))
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Total Bar

    private var totalBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Subtotal")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                Spacer()
                Text(subtotal.currency)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }

            Divider()

            HStack {
                Text("TOTAL")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Text(subtotal.currency)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.sweeplyBorder.opacity(0.5)), alignment: .top)
    }

    // MARK: - Create

    private func createInvoice() {
        guard let clientId = selectedClientId,
              let userId = session.userId,
              !lineItems.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            let clientName = selectedClient?.name ?? "Unknown Client"
            let newInvoice = Invoice(
                id: UUID(),
                clientId: clientId,
                clientName: clientName,
                amount: subtotal,
                status: .unpaid,
                createdAt: Date(),
                dueDate: dueDate,
                invoiceNumber: autoInvoiceNumber,
                notes: notes,
                lineItems: lineItems
            )

            let success = await invoicesStore.insert(newInvoice, userId: userId)

            await MainActor.run {
                isSubmitting = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = invoicesStore.lastError ?? "Failed to create invoice."
                }
            }
        }
    }
}

// MARK: - Line Item Row

private struct LineItemRow: View {
    @Binding var item: InvoiceLineItem
    let onDelete: () -> Void

    @State private var qtyString: String = ""
    @State private var priceString: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Description row
            HStack {
                TextField("Service description", text: $item.description)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 16)

            // Qty × price = total
            HStack(spacing: 8) {
                // Qty stepper
                HStack(spacing: 0) {
                    Button {
                        guard item.quantity > 1 else { return }
                        item.quantity -= 1
                        qtyString = formatQty(item.quantity)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 28, height: 28)
                    }

                    TextField("1", text: $qtyString)
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 36)
                        .onChange(of: qtyString) { _, newValue in
                            if let v = Double(newValue), v > 0 { item.quantity = v }
                        }

                    Button {
                        item.quantity += 1
                        qtyString = formatQty(item.quantity)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 28, height: 28)
                    }
                }
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("×")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)

                // Unit price
                HStack(spacing: 2) {
                    Text("$")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                    TextField("0.00", text: $priceString)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(minWidth: 60)
                        .onChange(of: priceString) { _, newValue in
                            if let v = Double(newValue) { item.unitPrice = v }
                        }
                }

                Spacer()

                // Row total
                Text(item.total.currency)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
        .onAppear {
            qtyString = formatQty(item.quantity)
            priceString = item.unitPrice > 0 ? String(format: "%.2f", item.unitPrice) : ""
        }
    }

    private func formatQty(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Service Picker Sheet

private struct ServicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let catalog: [BusinessService]
    let onSelect: (InvoiceLineItem) -> Void

    @State private var customDescription = ""
    @State private var customPriceString = ""
    @State private var showingCustom = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(catalog) { service in
                        Button {
                            onSelect(InvoiceLineItem(description: service.name, quantity: 1, unitPrice: service.price))
                            dismiss()
                        } label: {
                            HStack {
                                Text(service.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.sweeplyNavy)
                                Spacer()
                                Text(service.price.currency)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                        }
                    }
                } header: {
                    Text("FROM YOUR CATALOG")
                }

                Section {
                    if showingCustom {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Description", text: $customDescription)
                                .font(.system(size: 15))
                            HStack(spacing: 4) {
                                Text("$").foregroundStyle(Color.sweeplyTextSub)
                                TextField("Price", text: $customPriceString)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, design: .monospaced))
                            }
                            Button {
                                let price = Double(customPriceString) ?? 0
                                onSelect(InvoiceLineItem(description: customDescription, quantity: 1, unitPrice: price))
                                dismiss()
                            } label: {
                                Text("Add Custom Service")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyNavy)
                            }
                            .disabled(customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            withAnimation { showingCustom = true }
                        } label: {
                            Label("Add custom line item", systemImage: "plus.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                } header: {
                    Text("CUSTOM")
                }
            }
            .navigationTitle("Add Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Shared subviews

private struct InvoiceFormSectionHeader: View {
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

private struct InvoicePickerButton: View {
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}
