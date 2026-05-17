import SwiftUI

struct JobsDetailListView: View {
    @State private var selectedRange: RangeFilter = .month

    let status: JobStatus
    let jobs: [Job]

    private enum RangeFilter: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case sixMonths = "6 Months"
        case all = "All"
    }

    private var accentColor: Color {
        switch status {
        case .completed:              return .sweeplySuccess
        case .scheduled, .inProgress: return .sweeplyAccent
        case .cancelled:              return .sweeplyDestructive
        }
    }

    private var navTitle: String {
        switch status {
        case .completed:              return "Completed Jobs".translated()
        case .scheduled, .inProgress: return "Upcoming Jobs".translated()
        case .cancelled:              return "Cancelled Jobs".translated()
        }
    }

    private var filteredJobs: [Job] {
        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .all:
            return jobs
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return jobs }
            return jobs.filter { $0.date >= start && $0.date <= now }
        case .month:
            guard let start = calendar.date(byAdding: .month, value: -1, to: now) else { return jobs }
            return jobs.filter { $0.date >= start && $0.date <= now }
        case .sixMonths:
            guard let start = calendar.date(byAdding: .month, value: -6, to: now) else { return jobs }
            return jobs.filter { $0.date >= start && $0.date <= now }
        }
    }

    private var sortedJobs: [Job] {
        switch status {
        case .scheduled, .inProgress: return filteredJobs.sorted { $0.date < $1.date }
        default:                       return filteredJobs.sorted { $0.date > $1.date }
        }
    }

    private var totalValue: Double { filteredJobs.reduce(0) { $0 + $1.price } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryStrip

                if sortedJobs.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedJobs.enumerated()), id: \.element.id) { idx, job in
                            NavigationLink {
                                JobDetailView(jobId: job.id)
                            } label: {
                                JobDetailRow(job: job, accentColor: accentColor)
                            }
                            .buttonStyle(.plain)
                            if idx < sortedJobs.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 80)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(RangeFilter.allCases, id: \.self) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            if selectedRange == range {
                                Label(range.rawValue.translated(), systemImage: "checkmark")
                            } else {
                                Text(range.rawValue.translated())
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                }
            }
        }
    }

    private var summaryStrip: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(filteredJobs.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .monospacedDigit()
                Text(summaryLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            if status != .cancelled && totalValue > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(totalValue.currency)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("total value".translated())
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private var summaryLabel: String {
        switch selectedRange {
        case .week:
            return filteredJobs.count == 1 ? "job this week".translated() : "jobs this week".translated()
        case .month:
            return filteredJobs.count == 1 ? "job this month".translated() : "jobs this month".translated()
        case .sixMonths:
            return filteredJobs.count == 1 ? "job in last 6 months".translated() : "jobs in last 6 months".translated()
        case .all:
            return filteredJobs.count == 1 ? "job all time".translated() : "jobs all time".translated()
        }
    }

    private var emptyStateText: String {
        switch status {
        case .completed:              return emptyStateText(prefix: "completed")
        case .scheduled, .inProgress: return emptyStateText(prefix: "upcoming")
        case .cancelled:              return emptyStateText(prefix: "cancelled")
        }
    }

    private func emptyStateText(prefix: String) -> String {
        switch selectedRange {
        case .week:
            return "No \(prefix) jobs this week".translated()
        case .month:
            return "No \(prefix) jobs this month".translated()
        case .sixMonths:
            return "No \(prefix) jobs in the last 6 months".translated()
        case .all:
            return "No \(prefix) jobs".translated()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
            Text(emptyStateText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Row

private struct JobDetailRow: View {
    let job: Job
    let accentColor: Color

    private var dateStr: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: job.date)
    }

    private var timeStr: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: job.date)
    }

    private var serviceIcon: String {
        switch job.serviceType {
        case .standard:         return "house.fill"
        case .deep:             return "sparkles"
        case .moveInOut:        return "shippingbox.fill"
        case .postConstruction: return "hammer.fill"
        case .office:           return "building.2.fill"
        case .custom:           return "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.10))
                    .frame(width: 42, height: 42)
                Image(systemName: serviceIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.clientName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                Text(job.address)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.85))
                    if job.isRecurring {
                        HStack(spacing: 2) {
                            Image(systemName: "repeat")
                                .font(.system(size: 9, weight: .medium))
                            Text("Recurring".translated())
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(job.price.currency)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(dateStr)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
