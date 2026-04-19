import SwiftUI

struct CleanerUpcomingView: View {
    @Environment(JobsStore.self) private var jobsStore

    let membership: TeamMembership

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var statusFilter: JobStatus? = nil
    @State private var selectedJobId: UUID? = nil

    private let calendar = Calendar.current

    // 14-day window starting today
    private var weekDays: [Date] {
        (0..<14).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))
        }
    }

    private var jobsForSelectedDay: [Job] {
        jobsStore.jobs.filter {
            $0.assignedMemberId == membership.id
            && calendar.isDate($0.date, inSameDayAs: selectedDate)
            && $0.status != .cancelled
            && (statusFilter == nil || $0.status == statusFilter)
        }.sorted { $0.date < $1.date }
    }

    private func jobCount(for date: Date) -> Int {
        jobsStore.jobs.filter {
            $0.assignedMemberId == membership.id
            && calendar.isDate($0.date, inSameDayAs: date)
            && $0.status != .cancelled
        }.count
    }

    private var dayRevenue: Double {
        jobsForSelectedDay.reduce(0) { $0 + $1.price }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Page header
                    PageHeader(
                        eyebrow: "YOUR JOBS",
                        title: "Schedule",
                        subtitle: headerSubtitle
                    ) {
                        EmptyView()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // Week strip
                    weekStrip
                        .padding(.bottom, 12)

                    Divider()

                    // Filter pills
                    filterPills
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    // Stats bar
                    if !jobsForSelectedDay.isEmpty {
                        statsBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }

                    // Job list
                    if jobsStore.isLoading {
                        loadingView
                    } else if jobsForSelectedDay.isEmpty {
                        emptyState
                    } else {
                        jobList
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId)
            }
        }
    }

    // MARK: - Header Subtitle

    private var headerSubtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(weekDays, id: \.self) { day in
                    WeekDayCell(
                        date: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day),
                        jobCount: jobCount(for: day)
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(duration: 0.2)) {
                            selectedDate = day
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "All", isSelected: statusFilter == nil) {
                    withAnimation(.spring(duration: 0.2)) { statusFilter = nil }
                }
                FilterPill(label: "Scheduled", isSelected: statusFilter == .scheduled) {
                    withAnimation(.spring(duration: 0.2)) {
                        statusFilter = statusFilter == .scheduled ? nil : .scheduled
                    }
                }
                FilterPill(label: "In Progress", isSelected: statusFilter == .inProgress) {
                    withAnimation(.spring(duration: 0.2)) {
                        statusFilter = statusFilter == .inProgress ? nil : .inProgress
                    }
                }
                FilterPill(label: "Completed", isSelected: statusFilter == .completed) {
                    withAnimation(.spring(duration: 0.2)) {
                        statusFilter = statusFilter == .completed ? nil : .completed
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack {
            Text("\(jobsForSelectedDay.count) \(jobsForSelectedDay.count == 1 ? "job" : "jobs")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
            if dayRevenue > 0 {
                Text(dayRevenue.currency)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
        }
    }

    // MARK: - Job List

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(jobsForSelectedDay) { job in
                    CleanerScheduleJobRow(job: job)
                        .padding(.horizontal, 20)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedJobId = job.id
                        }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: calendar.isDateInToday(selectedDate) ? "sun.max" : "calendar.badge.checkmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            VStack(spacing: 6) {
                Text(calendar.isDateInToday(selectedDate) ? "You're all clear today" : "Nothing scheduled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(statusFilter == nil ? "No jobs for this day" : "No \(statusFilter!.rawValue.lowercased()) jobs")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sweeplySurface)
                        .frame(height: 80)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - WeekDayCell

private struct WeekDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let jobCount: Int
    let action: () -> Void

    private var dayAbbrev: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }
    private var dayNum: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(dayAbbrev)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? .white : Color.sweeplyTextSub)

                Text(dayNum)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)

                Circle()
                    .fill(isSelected ? Color.white.opacity(0.7) : Color.sweeplyAccent)
                    .frame(width: 5, height: 5)
                    .opacity(jobCount > 0 ? 1 : 0)
            }
            .frame(width: 44, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.sweeplyNavy : Color.sweeplySurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isToday && !isSelected ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: isToday && !isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FilterPill

private struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : Color.sweeplyTextSub)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.sweeplyNavy : Color.sweeplySurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.sweeplyNavy : Color.sweeplyBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CleanerScheduleJobRow

struct CleanerScheduleJobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 0) {
            // Left service-type accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(serviceColor(job.serviceType))
                .frame(width: 4)
                .padding(.vertical, 12)
                .padding(.trailing, 12)

            // Time column
            VStack(alignment: .center, spacing: 2) {
                Text(job.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(serviceColor(job.serviceType))
                if job.duration > 0 {
                    Text(durationLabel(job.duration))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .frame(width: 52)
            .padding(.vertical, 12)

            // Middle: client + service + address
            VStack(alignment: .leading, spacing: 3) {
                Text(job.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
                if !job.address.isEmpty {
                    Label(job.address, systemImage: "mappin")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)

            Spacer(minLength: 8)

            // Right: price + status badge
            VStack(alignment: .trailing, spacing: 4) {
                Text(job.price.currency)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                statusBadge(job.status)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 4)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func durationLabel(_ hours: Double) -> String {
        let total = Int(hours * 60)
        let h = total / 60; let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func statusBadge(_ status: JobStatus) -> some View {
        let color: Color = {
            switch status {
            case .scheduled:  return Color.sweeplyAccent
            case .inProgress: return .orange
            case .completed:  return .green
            case .cancelled:  return Color.sweeplyTextSub
            }
        }()
        return Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func serviceColor(_ type: ServiceType) -> Color {
        switch type {
        case .standard:         return Color.sweeplyAccent
        case .deep:             return Color.sweeplyNavy
        case .moveInOut:        return Color.sweeplyWarning
        case .postConstruction: return .gray
        case .office:           return Color.sweeplyNavy
        case .custom:           return Color.sweeplyAccent
        }
    }
}
