import SwiftUI

struct InvoiceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self) private var session
    @Environment(ProfileStore.self) private var profileStore

    let invoiceId: UUID

    private var invoice: Invoice? {
        invoicesStore.invoices.first(where: { $0.id == invoiceId })
    }

    private var client: Client? {
        guard let invoice else { return nil }
        return clientsStore.clients.first(where: { $0.id == invoice.clientId })
    }

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var pdfData: Data? = nil
    @State private var showPDFShare = false

    var body: some View {
        Group {
            if let invoice {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        invoiceHeader(invoice: invoice)
                        actionButtons(invoice: invoice)

                        if let client {
                            clientProfileCard(client: client)
                        }

                        if !invoice.lineItems.isEmpty {
                            lineItemsCard(invoice: invoice)
                        }

                        invoiceDetailsCard(invoice: invoice)

                        deleteButton(invoice: invoice)

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
                .background(Color.sweeplyBackground.ignoresSafeArea())
                .navigationTitle("Invoice Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showingEdit = true }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    EditInvoiceSheet(invoice: invoice)
                }
                .sheet(isPresented: $showPDFShare) {
                    ShareSheetView(data: pdfData ?? Data(), fileName: "Invoice-\(invoice.invoiceNumber).pdf")
                }
                .alert("Delete Invoice?", isPresented: $showingDeleteConfirm) {
                    Button("Delete", role: .destructive) { deleteInvoice(invoice) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete \(invoice.invoiceNumber). This can't be undone.")
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text("Invoice not found")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Button("Go Back") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sweeplyBackground)
            }
        }
    }

    // MARK: - Header

    private func invoiceHeader(invoice: Invoice) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text(invoice.total.currency)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
                InvoiceStatusBadge(status: invoice.status)
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.sweeplyAccent)
                Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                if invoice.status == .overdue {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Overdue")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.sweeplyDestructive)
                }
            }
            .padding(12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }

    // MARK: - Action Buttons

    private func actionButtons(invoice: Invoice) -> some View {
        HStack(spacing: 12) {
            if invoice.status != .paid {
                Button {
                    Task {
                        await invoicesStore.markPaid(id: invoice.id)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplySuccess)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Label("Already Paid", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplySurface)
                    .foregroundStyle(Color.sweeplySuccess)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                pdfData = generateInvoicePDF(invoice: invoice, businessName: profileStore.profile?.businessName ?? "My Business")
                showPDFShare = true
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Client Profile Card

    private func clientProfileCard(client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BILLED TO")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)

            NavigationLink(destination: ClientDetailView(clientId: client.id)) {
                SectionCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.sweeplyNavy.opacity(0.1))
                                .frame(width: 48, height: 48)
                            Text(String(client.name.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(client.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)

                            HStack(spacing: 4) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 10))
                                Text(client.email.isEmpty ? "No email listed" : client.email)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(Color.sweeplyTextSub)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyBorder)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Line Items Card

    private func lineItemsCard(invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SERVICES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)

            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(invoice.lineItems) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.description)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)
                                Text("\(formatQty(item.quantity)) × \(item.unitPrice.currency)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            Spacer()
                            Text(item.total.currency)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                        .padding(.vertical, 10)

                        if item.id != invoice.lineItems.last?.id {
                            Divider()
                        }
                    }

                    // Total row
                    Divider().padding(.top, 4)

                    HStack {
                        Text("TOTAL")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text(invoice.total.currency)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: - Invoice Details Card

    private func invoiceDetailsCard(invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOCUMENT DETAILS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)

            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    InvoiceInfoRow(icon: "doc.text.fill", title: "Invoice No.", value: invoice.invoiceNumber)
                    Divider()
                    InvoiceInfoRow(icon: "plus.circle.fill", title: "Issued", value: invoice.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Divider()
                    InvoiceInfoRow(icon: "exclamationmark.square.fill", title: "Due Date", value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))

                    if !invoice.notes.isEmpty {
                        Divider()
                        InvoiceInfoRow(icon: "note.text", title: "Notes", value: invoice.notes)
                    }
                }
            }
        }
    }

    // MARK: - Delete Button

    private func deleteButton(invoice: Invoice) -> some View {
        Button {
            showingDeleteConfirm = true
        } label: {
            HStack {
                if isDeleting {
                    ProgressView().tint(Color.sweeplyDestructive)
                } else {
                    Image(systemName: "trash")
                    Text("Delete Invoice")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.sweeplyDestructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.sweeplyDestructive.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyDestructive.opacity(0.2), lineWidth: 1))
        }
        .disabled(isDeleting)
    }

    // MARK: - Actions

    private func deleteInvoice(_ invoice: Invoice) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isDeleting = true
        Task {
            let _ = await invoicesStore.delete(id: invoice.id)
            await MainActor.run {
                isDeleting = false
                dismiss()
            }
        }
    }

    private func shareText(invoice: Invoice) -> String {
        var lines: [String] = []
        lines.append("Invoice \(invoice.invoiceNumber)")
        lines.append("Billed to: \(invoice.clientName)")
        lines.append("")

        if !invoice.lineItems.isEmpty {
            lines.append("Services:")
            for item in invoice.lineItems {
                lines.append("  \(item.description) × \(formatQty(item.quantity)) = \(item.total.currency)")
            }
        }

        lines.append("")
        lines.append("Total: \(invoice.total.currency)")
        lines.append("Due: \(invoice.dueDate.formatted(date: .long, time: .omitted))")

        if !invoice.notes.isEmpty {
            lines.append("")
            lines.append("Notes: \(invoice.notes)")
        }

        lines.append("")
        lines.append("Please make payment by the due date. Thank you!")

        return lines.joined(separator: "\n")
    }

    private func formatQty(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - PDF Generation

private func generateInvoicePDF(invoice: Invoice, businessName: String) -> Data {
    let pageWidth: CGFloat = 595
    let pageHeight: CGFloat = 842
    let margin: CGFloat = 40
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
    return renderer.pdfData { ctx in
        ctx.beginPage()
        let context = ctx.cgContext

        // Header bar
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 76)
        UIColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1).setFill()
        context.fill(headerRect)

        let businessAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        businessName.draw(at: CGPoint(x: margin, y: 24), withAttributes: businessAttrs)

        let invoiceLabel = "INVOICE"
        let invoiceAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]
        let invoiceLabelSize = (invoiceLabel as NSString).size(withAttributes: invoiceAttrs)
        (invoiceLabel as NSString).draw(at: CGPoint(x: pageWidth - margin - invoiceLabelSize.width, y: 30), withAttributes: invoiceAttrs)

        // Metadata
        var y: CGFloat = 100
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.label]
        let df = DateFormatter(); df.dateStyle = .medium

        func drawRow(_ label: String, _ value: String, at yPos: CGFloat, valueColor: UIColor = UIColor.label) {
            (label as NSString).draw(at: CGPoint(x: margin, y: yPos), withAttributes: labelAttrs)
            var va = valueAttrs; va[.foregroundColor] = valueColor
            (value as NSString).draw(at: CGPoint(x: margin + 120, y: yPos), withAttributes: va)
        }

        drawRow("Invoice #", invoice.invoiceNumber, at: y); y += 22
        drawRow("Date", df.string(from: invoice.createdAt), at: y); y += 22
        let overdueColor: UIColor = invoice.status == .overdue ? .systemRed : UIColor.label
        drawRow("Due", df.string(from: invoice.dueDate), at: y, valueColor: overdueColor); y += 22
        drawRow("Status", invoice.status.rawValue, at: y); y += 36

        // Client
        let billToAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.secondaryLabel]
        ("BILL TO" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: billToAttrs); y += 18
        let clientNameAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor.label]
        (invoice.clientName as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: clientNameAttrs); y += 36

        // Line items table header
        let tableX = margin; let col1W: CGFloat = 240; let col2W: CGFloat = 50; let col3W: CGFloat = 110; let col4W: CGFloat = 110
        let headerFill = CGRect(x: tableX, y: y, width: pageWidth - margin * 2, height: 26)
        UIColor(white: 0.93, alpha: 1).setFill(); context.fill(headerFill)
        let thAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.secondaryLabel]
        ("DESCRIPTION" as NSString).draw(at: CGPoint(x: tableX + 8, y: y + 7), withAttributes: thAttrs)
        ("QTY" as NSString).draw(at: CGPoint(x: tableX + col1W + 4, y: y + 7), withAttributes: thAttrs)
        ("UNIT" as NSString).draw(at: CGPoint(x: tableX + col1W + col2W + 4, y: y + 7), withAttributes: thAttrs)
        ("TOTAL" as NSString).draw(at: CGPoint(x: tableX + col1W + col2W + col3W + 4, y: y + 7), withAttributes: thAttrs)
        y += 28

        let items = invoice.lineItems.isEmpty
            ? [InvoiceLineItem(description: invoice.clientName.isEmpty ? "Service" : "Cleaning Service", quantity: 1, unitPrice: invoice.amount)]
            : invoice.lineItems

        for (i, item) in items.enumerated() {
            let rowRect = CGRect(x: tableX, y: y, width: pageWidth - margin * 2, height: 28)
            if i % 2 == 1 { UIColor(white: 0.97, alpha: 1).setFill(); context.fill(rowRect) }
            let cellAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.label]
            (item.description as NSString).draw(at: CGPoint(x: tableX + 8, y: y + 8), withAttributes: cellAttrs)
            (String(format: "%.0f", item.quantity) as NSString).draw(at: CGPoint(x: tableX + col1W + 4, y: y + 8), withAttributes: cellAttrs)
            (String(format: "$%.2f", item.unitPrice) as NSString).draw(at: CGPoint(x: tableX + col1W + col2W + 4, y: y + 8), withAttributes: cellAttrs)
            (String(format: "$%.2f", item.total) as NSString).draw(at: CGPoint(x: tableX + col1W + col2W + col3W + 4, y: y + 8), withAttributes: cellAttrs)
            y += 28
        }

        // Separator
        context.setStrokeColor(UIColor.separator.cgColor); context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y + 4)); context.addLine(to: CGPoint(x: pageWidth - margin, y: y + 4)); context.strokePath()
        y += 16

        // Total
        let totalLabelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor.label]
        let totalStr = String(format: "$%.2f", invoice.total)
        let totalSize = (totalStr as NSString).size(withAttributes: totalLabelAttrs)
        ("TOTAL" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: totalLabelAttrs)
        (totalStr as NSString).draw(at: CGPoint(x: pageWidth - margin - totalSize.width, y: y), withAttributes: totalLabelAttrs)
        y += 32

        // Notes
        if !invoice.notes.isEmpty {
            let notesLabelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.secondaryLabel]
            ("NOTES" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: notesLabelAttrs); y += 16
            let notesAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.label]
            (invoice.notes as NSString).draw(in: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 60), withAttributes: notesAttrs)
        }

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
        let footerStr = "Generated by Sweeply"
        let footerSize = (footerStr as NSString).size(withAttributes: footerAttrs)
        (footerStr as NSString).draw(at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: 810), withAttributes: footerAttrs)
    }
}

// MARK: - Share Sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let data: Data
    let fileName: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Edit Sheet

private struct EditInvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(AppSession.self) private var session

    let invoice: Invoice

    @State private var lineItems: [InvoiceLineItem]
    @State private var dueDate: Date
    @State private var notes: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(invoice: Invoice) {
        self.invoice = invoice
        _lineItems = State(initialValue: invoice.lineItems)
        _dueDate = State(initialValue: invoice.dueDate)
        _notes = State(initialValue: invoice.notes)
    }

    private var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.sweeplyDestructive)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Line items
                        if !lineItems.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                editSectionHeader("SERVICES")
                                VStack(spacing: 8) {
                                    ForEach($lineItems) { $item in
                                        EditLineItemRow(item: $item) {
                                            lineItems.removeAll { $0.id == item.id }
                                        }
                                    }
                                }
                            }
                        }

                        // Due date
                        VStack(alignment: .leading, spacing: 12) {
                            editSectionHeader("PAYMENT")
                            DatePicker("Due Date", selection: $dueDate, in: Date()..., displayedComponents: .date)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.sweeplySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 12) {
                            editSectionHeader("NOTES")
                            TextField("Notes (optional)", text: $notes, axis: .vertical)
                                .font(.system(size: 15))
                                .lineLimit(3...6)
                                .padding(16)
                                .background(Color.sweeplySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 100)
                }

                // Footer
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 16) {
                        Button("Cancel") { dismiss() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))

                        Button { saveChanges() } label: {
                            Group {
                                if isSubmitting { ProgressView().tint(.white) }
                                else { Text("Save Changes") }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(isSubmitting)
                    }
                    .padding(20)
                    .background(Color.sweeplyBackground.ignoresSafeArea(edges: .bottom))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .navigationTitle("Edit Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(false)
        }
    }

    private func editSectionHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
        }
    }

    private func saveChanges() {
        guard let userId = session.userId else { return }
        isSubmitting = true
        errorMessage = nil

        var updated = invoice
        updated.lineItems = lineItems
        updated.amount = subtotal
        updated.dueDate = dueDate
        updated.notes = notes

        Task {
            let success = await invoicesStore.update(updated, userId: userId)
            await MainActor.run {
                isSubmitting = false
                if success { dismiss() }
                else { errorMessage = invoicesStore.lastError ?? "Failed to save changes." }
            }
        }
    }
}

// MARK: - Edit Line Item Row (simplified for edit sheet)

private struct EditLineItemRow: View {
    @Binding var item: InvoiceLineItem
    let onDelete: () -> Void

    @State private var priceString: String = ""

    var body: some View {
        HStack(spacing: 12) {
            TextField("Description", text: $item.description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)

            Spacer()

            HStack(spacing: 2) {
                Text("$").font(.system(size: 13)).foregroundStyle(Color.sweeplyTextSub)
                TextField("0.00", text: $priceString)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: priceString) { _, newValue in
                        if let v = Double(newValue) { item.unitPrice = v }
                    }
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.sweeplyDestructive.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
        .onAppear {
            priceString = item.unitPrice > 0 ? String(format: "%.2f", item.unitPrice) : ""
        }
    }
}

// MARK: - Shared

private struct InvoiceInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
