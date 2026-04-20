import SwiftUI
import Charts

struct CleanerFinanceView: View {
    @Environment(JobsStore.self) private var jobsStore

    let membership: TeamMembership

    @AppStorage("cleanerFinancePeriod") private var selectedPeriodRaw: String = "This Month"
    @State private var appeared = false

    private var selectedPeriod: Period { Period(rawValue: selectedPeriodRaw) ?? .month }

    enum Period: String, CaseIterable {
        case week  = "This Week"
        case month = "This Month"
        case all   = "All Time"
    }

    // MARK: - Derived

    private var allMyJobs: [Job] {
        jobsStore.jobs.filter { $0.assignedMemberId == membership.id }
    }

    private var periodStart: Date? {
        let cal = Calendar.current
        switch selectedPeriod {
        case .week:  return cal.dateInterval(of: .weekOfYear, for: Date())?.start
        case .month: return cal.dateInterval(of: .month, for: Date())?.start
        case .all:   return nil
        }
    }

    private var completedJobs: [Job] {
        allMyJobs
            .filter { $0.status == .completed && (periodStart == nil || $0.date >= periodStart!) }
            .sorted { $0.date > $1.date }
    }

    private var upcomingEarningsJobs: [Job] {
        allMyJobs
            .filter { $0.status == .scheduled || $0.status == .inProgress }
            .sorted { $0.date < $1.date }
    }

    private var totalEarned: Double { completedJobs.reduce(0) { $0 + $1.price } }
    private var avgPerJob: Double   { completedJobs.isEmpty ? 0 : totalEarned / Double(completedJobs.count) }
    private var scheduledTotal: Double { upcomingEarningsJobs.reduce(0) { $0 + $1.price } }

    private var weeklyEarningsData: [(week: Date, amount: Double)] {
        let cal = Calendar.current; let today = Date()
        return (0..<8).reversed().compactMap { ago -> (Date, Double)? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -ago, to: cal.startOfDay(for: today)),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
            let total = allMyJobs
                .filter { $0.status == .completed && $0.date >= start && $0.date < end }
                .reduce(0.0) { $0 + $1.price }
            return (start, total)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    Divider()

                    heroStrip
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 8)

                    VStack(spacing: 12) {
                        completedSection
                        if !upcomingEarningsJobs.isEmpty { scheduledSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        PageHeader(eyebrow: "EARNINGS", title: "Finance", subtitle: selectedPeriod.rawValue) {
            periodPicker
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases, id: \.self) { period in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(duration: 0.2)) { selectedPeriodRaw = period.rawValue }
                } label: {
                    Text(period == .week ? "Wk" : period == .month ? "Mo" : "All")
                        .font(.system(size: 12, weight: selectedPeriod == period ? .bold : .medium))
                        .foregroundStyle(selectedPeriod == period ? .white : Color.sweeplyTextSub)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedPeriod == period ? Color.sweeplyNavy : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sweeplySurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Hero Strip

    private var heroStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statCell(value: totalEarned.currency, label: "Gross Earned")
                stripDivider
                statCell(value: "\(completedJobs.count)", label: "Jobs Done")
                stripDivider
                statCell(value: avgPerJob > 0 ? avgPerJob.currency : "—", label: "Avg / Job")
            }
            .padding(.vertical, 14)

            if !weeklyEarningsData.isEmpty {
                Chart(weeklyEarningsData, id: \.week) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        y: .value("Earned", point.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sweeplyAccent.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Earned", point.amount)
                    )
                    .foregroundStyle(Color.sweeplyAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 32)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Rate Info Banner

    private var rateInfoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.sweeplyAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your Pay Rate")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text("Contact your manager to set up your pay rate")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.sweeplyAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle().fill(Color.sweeplyBorder).frame(width: 1, height: 40)
    }

    // MARK: - Completed Jobs Section

    private var completedSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Completed Jobs", subtitle: selectedPeriod.rawValue, action: nil)

                if jobsStore.isLoading {
                    skeletonRows
                } else if completedJobs.isEmpty {
                    emptyCompletedState
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(completedJobs.enumerated()), id: \.element.id) { index, job in
                            financeJobRow(job: job, showPrice: true)
                            if index < completedJobs.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }

                    Divider().padding(.top, 8)

                    HStack {
                        Text("Total")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(totalEarned.currency)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var emptyCompletedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyAccent.opacity(0.4))
            Text("No completed jobs \(selectedPeriod == .all ? "yet" : "this period")")
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Scheduled Earnings Section

    private var scheduledSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Upcoming Earnings", subtitle: "Scheduled jobs", action: nil)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(upcomingEarningsJobs.prefix(5).enumerated()), id: \.element.id) { index, job in
                        financeJobRow(job: job, showPrice: true)
                        if index < min(upcomingEarningsJobs.count, 5) - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }

                if scheduledTotal > 0 {
                    Divider().padding(.top, 8)
                    HStack {
                        Text("Potential")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Text(scheduledTotal.currency)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Row

    private func financeJobRow(job: Job, showPrice: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(job.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(job.status == .completed ? .green : Color.sweeplyAccent)
                Rectangle()
                    .fill((job.status == .completed ? Color.green : Color.sweeplyAccent).opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 52)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.vertical, 10)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(job.price.currency)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(job.status == .completed ? Color.sweeplyNavy : Color.sweeplyAccent)
                statusPill(job.status)
            }
        }
    }

    private func statusPill(_ status: JobStatus) -> some View {
        let color: Color = status == .completed ? .green : status == .inProgress ? .orange : Color.sweeplyAccent
        return Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var skeletonRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.sweeplyBorder.opacity(0.4))
                    .frame(height: 52)
            }
        }
    }
}
