import SwiftUI

struct ClientDetailView: View {
    let client: Client
    let allJobs: [Job]
    let allInvoices: [Invoice]

    @Environment(\.dismiss) private var dismiss

    private var clientJobs: [Job] {
        allJobs.filter { $0.clientId == client.id }.sorted { $0.date > $1.date }
    }

    private var clientInvoices: [Invoice] {
        allInvoices.filter { $0.clientId == client.id }.sorted { $0.createdAt > $1.createdAt }
    }

    private var totalRevenue: Double {
        clientInvoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
    }

    private var outstanding: Double {
        clientInvoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileHeader
                statsRow
                if !client.entryInstructions.isEmpty || !client.notes.isEmpty {
                    notesCard
                }
                jobsSection
                invoicesSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(client.name)
    }

    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 20) {
            // Avatar & Basic Info
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.sweeplyNavy)
                        .frame(width: 64, height: 64)
                    Text(String(client.name.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(client.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    
                    if let service = client.preferredService {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text(service.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    } else {
                        Text("No preferred service")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                }
                Spacer()
            }

            // Contact Info
            VStack(alignment: .leading, spacing: 12) {
                if !client.address.isEmpty {
                    ContactRow(icon: "mappin.circle.fill", text: "\(client.address), \(client.city)")
                }
                if !client.phone.isEmpty {
                    ContactRow(icon: "phone.fill", text: client.phone)
                }
                if !client.email.isEmpty {
                    ContactRow(icon: "envelope.fill", text: client.email)
                }
            }
            .padding(.top, 4)

            // Quick Actions
            HStack(spacing: 12) {
                QuickActionButton(icon: "phone.fill", label: "Call", color: .green) {
                    callClient()
                }
                QuickActionButton(icon: "envelope.fill", label: "Email", color: .blue) {
                    emailClient()
                }
                QuickActionButton(icon: "map.fill", label: "Navigate", color: Color.sweeplyNavy) {
                    navigateClient()
                }
            }
        }
        .padding(24)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func callClient() {
        if let url = URL(string: "tel://\(client.phone.filter { $0.isNumber })") {
            UIApplication.shared.open(url)
        }
    }

    private func emailClient() {
        if let url = URL(string: "mailto:\(client.email)") {
            UIApplication.shared.open(url)
        }
    }

    private func navigateClient() {
        let addr = "\(client.address), \(client.city), \(client.state) \(client.zip)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?daddr=\(addr)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: 0) {
            StatCell(label: "Total Revenue", value: totalRevenue.currency, valueColor: .sweeplySuccess)
            dividerLine
            StatCell(label: "Outstanding", value: outstanding.currency, valueColor: outstanding > 0 ? .sweeplyWarning : .sweeplyTextSub)
            dividerLine
            StatCell(label: "Total Jobs", value: "\(clientJobs.count)")
        }
        .padding(.vertical, 16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    // MARK: - Notes Card
    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !client.entryInstructions.isEmpty {
                NoteRow(icon: "key.fill", label: "Entry Instructions", text: client.entryInstructions)
            }
            if !client.entryInstructions.isEmpty && !client.notes.isEmpty {
                Divider()
            }
            if !client.notes.isEmpty {
                NoteRow(icon: "note.text", label: "Notes", text: client.notes)
            }
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Jobs Section
    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Job History", count: clientJobs.count)

            if clientJobs.isEmpty {
                emptyState(icon: "briefcase", message: "No jobs with this client yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(clientJobs.prefix(10)) { job in
                        DetailJobRow(job: job)
                    }
                }
            }
        }
    }

    // MARK: - Invoices Section
    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Invoice History", count: clientInvoices.count)

            if clientInvoices.isEmpty {
                emptyState(icon: "doc.text", message: "No invoices for this client yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(clientInvoices.prefix(10)) { invoice in
                        DetailInvoiceRow(invoice: invoice)
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyTextSub)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.sweeplyBackground)
                .clipShape(Capsule())
            Spacer()
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

// MARK: - Sub-components

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct ContactRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
        }
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    var valueColor: Color = Color.primary

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NoteRow: View {
    let icon: String
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.3)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary)
            }
        }
    }
}

private struct DetailJobRow: View {
    let job: Job

    var body: some View {
        ZStack(alignment: .leading) {
            Color.sweeplySurface
            
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(job.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .frame(width: 65, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    
                    HStack(spacing: 6) {
                        StatusBadge(status: job.status)
                    }
                }
                
                Spacer()
                
                Text(job.price.currency)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: return Color.sweeplySuccess
        case .inProgress: return .orange
        case .scheduled: return Color.sweeplyBorder
        case .cancelled: return Color.sweeplyDestructive
        }
    }
}

private struct DetailInvoiceRow: View {
    let invoice: Invoice

    private var statusColor: Color {
        switch invoice.status {
        case .paid:    return Color.sweeplySuccess
        case .unpaid:  return Color.sweeplyWarning
        case .overdue: return Color.sweeplyDestructive
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.invoiceNumber)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            HStack(spacing: 8) {
                Text(invoice.amount.currency)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(invoice.status.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.10))
                    .overlay(Capsule().stroke(statusColor.opacity(0.20), lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClientDetailView(
            client: MockData.clients[0],
            allJobs: MockData.makeJobs(),
            allInvoices: MockData.makeInvoices()
        )
    }
}
