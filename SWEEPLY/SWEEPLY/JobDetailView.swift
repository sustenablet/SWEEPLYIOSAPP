import SwiftUI

struct JobDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore

    let jobId: UUID
    @State private var showInvoiceSheet = false

    private var job: Job? {
        jobsStore.jobs.first(where: { $0.id == jobId })
    }

    private var client: Client? {
        guard let job else { return nil }
        return clientsStore.clients.first(where: { $0.id == job.clientId })
    }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        jobHeader(job: job)
                        actionButtons(job: job)
                        
                        if let client {
                            clientProfileCard(client: client)
                        }

                        if let client = client, !client.entryInstructions.isEmpty || !client.notes.isEmpty {
                            propertyNotesCard(client: client)
                        }
                        
                        jobDetailsCard(job: job)

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
                .background(Color.sweeplyBackground.ignoresSafeArea())
                .navigationTitle("Job Details")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showInvoiceSheet) {
                    NewInvoiceView(prefill: job)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.square")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text("Job not found")
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
    private func jobHeader(job: Job) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(job.price.currency)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy.opacity(0.8))
                }
                Spacer()
                StatusBadge(status: job.status)
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.sweeplyAccent)
                Text(job.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                if job.isRecurring {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Recurring")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.sweeplyAccent)
                }
            }
            .padding(12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }

    // MARK: - Action Buttons
    private func actionButtons(job: Job) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if job.status != .completed {
                    Button {
                        Task { await jobsStore.updateStatus(id: job.id, status: .completed) }
                    } label: {
                        Label("Complete Job", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sweeplySuccess)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Button {
                        Task { await jobsStore.updateStatus(id: job.id, status: .scheduled) }
                    } label: {
                        Label("Re-open Job", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sweeplySurface)
                            .foregroundStyle(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }

                Button {
                    let addr = job.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(addr)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Navigate", systemImage: "location.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplyNavy)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            // Create Invoice — visible once the job is completed
            if job.status == .completed {
                Button {
                    showInvoiceSheet = true
                } label: {
                    Label("Create Invoice", systemImage: "doc.text.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplyAccent.opacity(0.12))
                        .foregroundStyle(Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyAccent.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Client Profile Card
    private func clientProfileCard(client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT PROFILE")
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
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 10))
                                Text(client.phone.isEmpty ? "No phone listed" : client.phone)
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

    // MARK: - Property Notes
    private func propertyNotesCard(client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROPERTY INSTRUCTIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    if !client.entryInstructions.isEmpty {
                        JobInfoRow(icon: "key.fill", title: "Entry", value: client.entryInstructions)
                    }
                    if !client.entryInstructions.isEmpty && !client.notes.isEmpty {
                        Divider()
                    }
                    if !client.notes.isEmpty {
                        JobInfoRow(icon: "doc.text.fill", title: "Internal Notes", value: client.notes)
                    }
                }
            }
        }
    }

    // MARK: - Job Details
    private func jobDetailsCard(job: Job) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JOB DETAILS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    JobInfoRow(icon: "mappin.and.ellipse", title: "Location", value: job.address.isEmpty ? "No address provided" : job.address)
                    Divider()
                    JobInfoRow(icon: "clock.fill", title: "Est. Duration", value: "\(Int(job.duration)) Hours")
                    Divider()
                    JobInfoRow(icon: "tag.fill", title: "Price", value: job.price.currency)
                }
            }
        }
    }
}

private struct JobInfoRow: View {
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
