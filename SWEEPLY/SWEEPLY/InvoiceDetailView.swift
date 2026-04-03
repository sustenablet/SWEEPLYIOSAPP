import SwiftUI

struct InvoiceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ClientsStore.self) private var clientsStore

    let invoiceId: UUID

    private var invoice: Invoice? {
        invoicesStore.invoices.first(where: { $0.id == invoiceId })
    }

    private var client: Client? {
        guard let invoice else { return nil }
        return clientsStore.clients.first(where: { $0.id == invoice.clientId })
    }

    @State private var showingShareSheet = false

    var body: some View {
        Group {
            if let invoice {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        invoiceHeader(invoice: invoice)
                        actionButtons(invoice: invoice)
                        
                        if let client {
                            clientProfileCard(client: client)
                        }

                        invoiceDetailsCard(invoice: invoice)

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
                .background(Color.sweeplyBackground.ignoresSafeArea())
                .navigationTitle("Invoice Details")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text("Invoice not found")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Button("Go Back") {
                        dismiss()
                    }
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
                    Text(invoice.amount.currency)
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
                    Task { await invoicesStore.markPaid(id: invoice.id) }
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
                Button {
                    // Reset to unpaid (optional functionality, left as visual state indicator)
                } label: {
                    Label("Already Paid", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplySurface)
                        .foregroundStyle(Color.sweeplySuccess)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
                .disabled(true)
            }
            
            Button {
                showingShareSheet = true
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                // Future Implementation: Real PDF generation
                Text("Sharing Invoice \(invoice.invoiceNumber) for \(invoice.amount.currency)...")
                    .presentationDetents([.height(200)])
            }
        }
    }

    @State private var showShareSheet = false

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

    // MARK: - Details Card
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
                    InvoiceInfoRow(icon: "plus.circle.fill", title: "Issued Date", value: invoice.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Divider()
                    InvoiceInfoRow(icon: "exclamationmark.square.fill", title: "Due Date", value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }
}

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
