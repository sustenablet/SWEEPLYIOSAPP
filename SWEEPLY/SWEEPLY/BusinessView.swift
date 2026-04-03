import SwiftUI

struct BusinessView: View {
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self)  private var profileStore

    @State private var appeared = false

    private var profile: UserProfile {
        profileStore.profile ?? MockData.profile
    }

    private var businessJobs: [Job] {
        jobsStore.jobs.isEmpty ? MockData.makeJobs() : jobsStore.jobs
    }

    private var businessInvoices: [Invoice] {
        invoicesStore.invoices.isEmpty ? MockData.makeAllInvoices() : invoicesStore.invoices
    }

    private var totalRevenue: Double {
        businessInvoices
            .filter { $0.status == .paid }
            .reduce(0) { $0 + $1.amount }
    }

    private var outstandingRevenue: Double {
        businessInvoices
            .filter { $0.status != .paid }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthlyJobs: [Job] {
        let calendar = Calendar.current
        return businessJobs.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var completedJobsThisMonth: Int {
        monthlyJobs.filter { $0.status == .completed }.count
    }

    private var upcomingJobs: [Job] {
        businessJobs
            .filter { $0.date >= Date() && $0.status != .cancelled }
            .sorted { $0.date < $1.date }
    }

    private var activeClientsCount: Int {
        Set(monthlyJobs.map(\.clientId)).count
    }

    private var averageTicket: Double {
        guard completedJobsThisMonth > 0 else { return 0 }
        let completedRevenue = monthlyJobs
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.price }
        return completedRevenue / Double(completedJobsThisMonth)
    }

    private var nextJob: Job? {
        upcomingJobs.first
    }

    private var serviceMix: [(label: String, percentage: Double, count: Int)] {
        let grouped = Dictionary(grouping: monthlyJobs, by: \.serviceType)
        let total = max(monthlyJobs.count, 1)

        return ServiceType.allCases.compactMap { service in
            let count = grouped[service]?.count ?? 0
            guard count > 0 else { return nil }
            return (service.rawValue, Double(count) / Double(total), count)
        }
        .sorted { $0.count > $1.count }
    }

    private var topClients: [(name: String, jobs: Int, revenue: Double)] {
        let grouped = Dictionary(grouping: monthlyJobs, by: \.clientId)

        return grouped.compactMap { _, jobs in
            guard let first = jobs.first else { return nil }
            return (
                name: first.clientName,
                jobs: jobs.count,
                revenue: jobs.reduce(0) { $0 + $1.price }
            )
        }
        .sorted { lhs, rhs in
            if lhs.jobs == rhs.jobs {
                return lhs.revenue > rhs.revenue
            }
            return lhs.jobs > rhs.jobs
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                PageHeader(
                    eyebrow: profile.businessName.isEmpty ? "Business" : profile.businessName.uppercased(),
                    title: "Operational Overview",
                    subtitle: "Preferences, performance, and support"
                )
                .padding(.top, 16)

                // 1. Performance KPIs
                HStack(spacing: 12) {
                    KPIBlock(title: "Active Clients", value: "\(activeClientsCount)", icon: "person.2.fill")
                    KPIBlock(title: "Jobs This Month", value: "\(monthlyJobs.count)", icon: "briefcase.fill")
                    KPIBlock(title: "Collected", value: totalRevenue.currency, icon: "dollarsign.circle.fill")
                }

                // 2. Snapshot
                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: "Business Snapshot", subtitle: "How the operation is moving this month", action: nil)
                        Divider()

                        snapshotRow(
                            title: "Completed Jobs",
                            value: "\(completedJobsThisMonth)",
                            detail: "\(monthlyJobs.count - completedJobsThisMonth) still in flight",
                            accent: .sweeplyAccent
                        )
                        Divider()
                        snapshotRow(
                            title: "Average Ticket",
                            value: averageTicket.currency,
                            detail: "Based on completed visits this month",
                            accent: .sweeplyNavy
                        )
                        Divider()
                        snapshotRow(
                            title: "Outstanding",
                            value: outstandingRevenue.currency,
                            detail: "Open invoices waiting to be collected",
                            accent: .sweeplyWarning
                        )
                    }
                }

                // 3. Next Job
                SectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        CardHeader(title: "Next Up", subtitle: "Your nearest scheduled visit", action: nil)

                        if let nextJob {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(nextJob.clientName)
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyNavy)
                                    Spacer()
                                    StatusBadge(status: nextJob.status)
                                }

                                Text(nextJob.serviceType.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)

                                Label(nextJob.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)

                                Label(nextJob.address, systemImage: "mappin.and.ellipse")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                    .lineLimit(2)

                                HStack(spacing: 12) {
                                    overviewChip(title: "Value", value: nextJob.price.currency)
                                    overviewChip(title: "Duration", value: durationLabel(for: nextJob.duration))
                                }
                            }
                        } else {
                            overviewEmptyState(
                                icon: "calendar.badge.checkmark",
                                title: "No upcoming jobs",
                                message: "When new visits are scheduled, the next one will appear here."
                            )
                        }
                    }
                }

                // 4. Service Distribution
                SectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        CardHeader(title: "Service Distribution", subtitle: "Most requested services this month", action: nil)

                        if serviceMix.isEmpty {
                            overviewEmptyState(
                                icon: "chart.bar.xaxis",
                                title: "No service mix yet",
                                message: "Once jobs are scheduled this month, the service split will show here."
                            )
                        } else {
                            VStack(spacing: 14) {
                                ForEach(serviceMix, id: \.label) { service in
                                    ServiceMixRow(label: service.label, percentage: service.percentage, count: service.count)
                                }
                            }
                        }
                    }
                }

                // 5. Top Clients
                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Top Clients", subtitle: "Highest activity this month", action: nil)

                        if topClients.isEmpty {
                            overviewEmptyState(
                                icon: "person.3.sequence",
                                title: "No client activity yet",
                                message: "Client rankings will update as jobs are completed."
                            )
                        } else {
                            Divider()
                            ForEach(Array(topClients.prefix(3).enumerated()), id: \.offset) { index, client in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(client.name)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("\(client.jobs) visits this month")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                    }

                                    Spacer()

                                    Text(client.revenue.currency)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyNavy)
                                }
                                .padding(.vertical, 4)

                                if index < min(topClients.count, 3) - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
    }

    private func snapshotRow(title: String, value: String, detail: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
    }

    private func overviewChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func overviewEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.45))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func durationLabel(for duration: Double) -> String {
        if duration == floor(duration) {
            return "\(Int(duration))h"
        }
        return String(format: "%.1fh", duration)
    }
}

// MARK: - Subviews

private struct KPIBlock: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ServiceMixRow: View {
    let label: String
    let percentage: Double
    let count: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(count) jobs").font(.system(size: 11)).foregroundStyle(Color.sweeplyTextSub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sweeplyBorder.opacity(0.5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sweeplyNavy.opacity(0.8))
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    BusinessView()
        .environment(AppSession())
        .environment(ProfileStore())
}
