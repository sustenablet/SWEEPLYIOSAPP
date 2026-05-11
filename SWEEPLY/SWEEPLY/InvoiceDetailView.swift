import SwiftUI
import PDFKit

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
    @State private var showPDFPreview = false

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
                .navigationTitle("Invoice Details".translated())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit".translated()) { showingEdit = true }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    EditInvoiceSheet(invoice: invoice)
                }
                .sheet(isPresented: $showMarkPaidSheet) {
                    MarkPaidSheet(invoice: invoice)
                }
                .sheet(isPresented: $showPDFShare) {
                    ShareSheetView(data: pdfData ?? Data(), fileName: "Invoice-\(invoice.invoiceNumber).pdf")
                }
                .sheet(isPresented: $showPDFPreview) {
                    NavigationStack {
                        PDFPreviewView(data: pdfData ?? Data())
                            .navigationTitle("Invoice Preview".translated())
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Close".translated()) { showPDFPreview = false }
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(action: { showPDFPreview = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showPDFShare = true } }) {
                                        Label("Share".translated(), systemImage: "square.and.arrow.up")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.sweeplyNavy)
                                    }
                                }
                            }
                    }
                }
                .alert("Delete Invoice?", isPresented: $showingDeleteConfirm) {
                    Button("Delete".translated(), role: .destructive) { deleteInvoice(invoice) }
                    Button("Cancel".translated(), role: .cancel) {}
                } message: {
                    Text("This will permanently delete %@. This can't be undone.".translated(with: invoice.invoiceNumber))
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text("Invoice not found".translated())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Button("Go Back".translated()) { dismiss() }
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
                        Text("Overdue".translated())
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

    @State private var showMarkPaidSheet = false
    
    // MARK: - Action Buttons

    private func actionButtons(invoice: Invoice) -> some View {
        HStack(spacing: 12) {
            if invoice.status != .paid {
                Button {
                    showMarkPaidSheet = true
                } label: {
                    Label("Mark Paid".translated(), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplySuccess)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Label("Already Paid".translated(), systemImage: "checkmark.seal.fill")
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
                showPDFPreview = true
            } label: {
                Label("Send".translated(), systemImage: "paperplane.fill")
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
            Text("BILLED TO".translated())
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
            Text("SERVICES".translated())
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
                        Text("TOTAL".translated())
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
            Text("DOCUMENT DETAILS".translated())
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
                    Text("Delete Invoice".translated())
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
    let margin: CGFloat = 48
    let navyColor = UIColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1)
    let accentColor = UIColor(red: 0.29, green: 0.76, blue: 0.53, alpha: 1) // sweeplyAccent
    let lightGray = UIColor(white: 0.96, alpha: 1)
    let df = DateFormatter(); df.dateStyle = .medium

    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
    return renderer.pdfData { ctx in
        ctx.beginPage()
        let context = ctx.cgContext

        // ─── 2-COLUMN HEADER ───────────────────────────────────
        var y: CGFloat = margin

        // Left: Business name + address
        let bizNameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: navyColor
        ]
        (businessName as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: bizNameAttrs)

        // Right: "INVOICE" large
        let invoiceTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .heavy),
            .foregroundColor: navyColor
        ]
        let invoiceTitle = "INVOICE"
        let titleSize = (invoiceTitle as NSString).size(withAttributes: invoiceTitleAttrs)
        (invoiceTitle as NSString).draw(
            at: CGPoint(x: pageWidth - margin - titleSize.width, y: y),
            withAttributes: invoiceTitleAttrs
        )
        y += 28

        // Sub-labels right column
        let metaLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let metaValueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: navyColor
        ]
        let overdueValueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.systemRed
        ]

        func drawRightMeta(label: String, value: String, yPos: CGFloat, highlight: Bool = false) {
            let labelStr = label as NSString
            let valueStr = value as NSString
            let valueAttrs = highlight ? overdueValueAttrs : metaValueAttrs
            let valueSize = valueStr.size(withAttributes: valueAttrs)
            let labelSize = labelStr.size(withAttributes: metaLabelAttrs)
            labelStr.draw(at: CGPoint(x: pageWidth - margin - valueSize.width - labelSize.width - 8, y: yPos), withAttributes: metaLabelAttrs)
            valueStr.draw(at: CGPoint(x: pageWidth - margin - valueSize.width, y: yPos), withAttributes: valueAttrs)
        }

        drawRightMeta(label: "No.  ", value: invoice.invoiceNumber, yPos: y)
        y += 16
        drawRightMeta(label: "Issued  ", value: df.string(from: invoice.createdAt), yPos: y)
        y += 16
        drawRightMeta(label: "Due  ", value: df.string(from: invoice.dueDate), yPos: y, highlight: invoice.status == .overdue)
        y += 24

        // ─── HORIZONTAL RULE ───────────────────────────────────
        context.setStrokeColor(navyColor.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        context.strokePath()
        y += 20

        // ─── BILL TO ───────────────────────────────────────────
        let billToLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let billToValueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: navyColor
        ]
        ("BILL TO" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: billToLabelAttrs)
        y += 14
        (invoice.clientName as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: billToValueAttrs)
        y += 32

        // ─── LINE ITEMS TABLE ──────────────────────────────────
        let tableX: CGFloat = margin
        let tableWidth = pageWidth - margin * 2
        let col1W: CGFloat = tableWidth * 0.48  // Description
        let col2W: CGFloat = tableWidth * 0.12  // Qty
        let col3W: CGFloat = tableWidth * 0.20  // Unit Price
        let col4W: CGFloat = tableWidth * 0.20  // Total (right-aligned)

        // Table header background
        let thRect = CGRect(x: tableX, y: y, width: tableWidth, height: 24)
        navyColor.setFill(); context.fill(thRect)

        let thAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        func rightAlign(_ str: String, in rect: CGRect, attrs: [NSAttributedString.Key: Any]) {
            let size = (str as NSString).size(withAttributes: attrs)
            (str as NSString).draw(at: CGPoint(x: rect.maxX - size.width - 6, y: rect.minY + 7), withAttributes: attrs)
        }

        ("DESCRIPTION" as NSString).draw(at: CGPoint(x: tableX + 8, y: y + 7), withAttributes: thAttrs)
        rightAlign("QTY", in: CGRect(x: tableX + col1W, y: y, width: col2W, height: 24), attrs: thAttrs)
        rightAlign("UNIT PRICE", in: CGRect(x: tableX + col1W + col2W, y: y, width: col3W, height: 24), attrs: thAttrs)
        rightAlign("TOTAL", in: CGRect(x: tableX + col1W + col2W + col3W, y: y, width: col4W, height: 24), attrs: thAttrs)
        y += 24

        let items = invoice.lineItems.isEmpty
            ? [InvoiceLineItem(description: "Cleaning Service", quantity: 1, unitPrice: invoice.amount)]
            : invoice.lineItems

        for (i, item) in items.enumerated() {
            let rowH: CGFloat = 28
            let rowRect = CGRect(x: tableX, y: y, width: tableWidth, height: rowH)
            if i % 2 == 0 {
                UIColor.white.setFill()
            } else {
                lightGray.setFill()
            }
            context.fill(rowRect)

            let cellAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.label
            ]
            let monoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            (item.description as NSString).draw(at: CGPoint(x: tableX + 8, y: y + 8), withAttributes: cellAttrs)
            rightAlign(String(format: "%.0f", item.quantity), in: CGRect(x: tableX + col1W, y: y, width: col2W, height: rowH), attrs: monoAttrs)
            rightAlign(String(format: "$%.2f", item.unitPrice), in: CGRect(x: tableX + col1W + col2W, y: y, width: col3W, height: rowH), attrs: monoAttrs)
            rightAlign(String(format: "$%.2f", item.total), in: CGRect(x: tableX + col1W + col2W + col3W, y: y, width: col4W, height: rowH), attrs: monoAttrs)
            y += rowH
        }

        // Border-top line before totals
        context.setStrokeColor(navyColor.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: tableX, y: y + 8))
        context.addLine(to: CGPoint(x: tableX + tableWidth, y: y + 8))
        context.strokePath()
        y += 20

        // Subtotal row
        let subLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let subValueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let totalBoldAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .bold),
            .foregroundColor: navyColor
        ]
        let totalLabelBoldAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: navyColor
        ]

        let subtotalStr = String(format: "$%.2f", invoice.subtotal)
        let subValSize = (subtotalStr as NSString).size(withAttributes: subValueAttrs)
        ("Subtotal" as NSString).draw(at: CGPoint(x: tableX, y: y), withAttributes: subLabelAttrs)
        (subtotalStr as NSString).draw(at: CGPoint(x: tableX + tableWidth - subValSize.width, y: y), withAttributes: subValueAttrs)
        y += 20

        // Total (bold)
        let totalStr = String(format: "$%.2f", invoice.total)
        let totalValSize = (totalStr as NSString).size(withAttributes: totalBoldAttrs)
        ("TOTAL DUE" as NSString).draw(at: CGPoint(x: tableX, y: y), withAttributes: totalLabelBoldAttrs)
        (totalStr as NSString).draw(at: CGPoint(x: tableX + tableWidth - totalValSize.width, y: y), withAttributes: totalBoldAttrs)
        y += 32

        // Notes
        if !invoice.notes.isEmpty {
            let notesLabelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: UIColor.secondaryLabel]
            ("NOTES" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: notesLabelAttrs); y += 14
            let notesAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.label]
            (invoice.notes as NSString).draw(in: CGRect(x: margin, y: y, width: tableWidth, height: 60), withAttributes: notesAttrs)
            y += 70
        }

        // ─── FOOTER ───────────────────────────────────────────
        let footerY: CGFloat = pageHeight - 52
        context.setStrokeColor(navyColor.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: footerY - 8))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: footerY - 8))
        context.strokePath()

        let footerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.tertiaryLabel]
        let footerLeft = "Payment due \(df.string(from: invoice.dueDate)). Thank you for your business."
        let footerRight = "Powered by Sweeply"
        (footerLeft as NSString).draw(at: CGPoint(x: margin, y: footerY), withAttributes: footerAttrs)
        let rightSize = (footerRight as NSString).size(withAttributes: footerAttrs)
        (footerRight as NSString).draw(at: CGPoint(x: pageWidth - margin - rightSize.width, y: footerY), withAttributes: footerAttrs)
    }
}

// MARK: - PDF Preview

private struct PDFPreviewView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = UIColor.systemBackground
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
        return pdfView
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            uiView.document = document
        }
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
                                editSectionHeader("SERVICES".translated())
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
                        Button("Cancel".translated()) { dismiss() }
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
                                else { Text("Save Changes".translated()) }
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
            .navigationTitle("Edit Invoice".translated())
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
