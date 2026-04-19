import SwiftUI

// MARK: - Cleaner Schedule View

enum CleanerScheduleMode: String, CaseIterable {
    case day  = "Day"
    case list = "List"
}

struct CleanerUpcomingView: View {
    @Environment(JobsStore.self)  private var jobsStore
    @Environment(AppSession.self) private var session

    let membership: TeamMembership

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var viewMode: CleanerScheduleMode = .day
    @State private var statusFilter: JobStatus? = nil
    @State private var showMonthPicker = false
    @State private var selectedJobId: UUID? = nil

    private let calendar: Calendar = {
        var c = Calendar.current; c.firstWeekday = 1; return c
    }()

    private let timelineHourHeight: CGFloat = 68
    private let timelineStartHour: Int = 6
    private let timelineEndHour: Int = 21

    // MARK: - Derived

    private var myJobs: [Job] {
        jobsStore.jobs.filter { $0.assignedMemberId == membership.id && $0.status != .cancelled }
    }

    private var filteredJobsForDay: [Job] {
        myJobs
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .filter { statusFilter == nil || $0.status == statusFilter }
            .sorted { $0.date < $1.date }
    }

    private var upcomingGroupedJobs: [(date: Date, jobs: [Job])] {
        let today = calendar.startOfDay(for: Date())
        let upcoming = myJobs
            .filter {
                calendar.startOfDay(for: $0.date) >= today
                && (statusFilter == nil || $0.status == statusFilter)
            }
            .sorted { $0.date < $1.date }
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (date: $0.key, jobs: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.date < $1.date }
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDay)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topToolbar

                modeSegment
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                WeekStripView(selectedDay: $selectedDay, jobs: myJobs)
                    .padding(.top, 12)

                Group {
                    switch viewMode {
                    case .day:  dayView
                    case .list: listView
                    }
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId)
            }
            .sheet(isPresented: $showMonthPicker) {
                CleanerMonthPicker(selectedDay: $selectedDay, jobs: myJobs)
                    .presentationDetents([.fraction(0.65)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)

                Button { showMonthPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(monthTitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            HeaderIconButton(systemName: statusFilter == nil
                             ? "line.3.horizontal.decrease.circle"
                             : "line.3.horizontal.decrease.circle.fill") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                cycleStatusFilter()
            }
        }
        .frame(minHeight: 76, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func cycleStatusFilter() {
        switch statusFilter {
        case nil:         statusFilter = .scheduled
        case .scheduled:  statusFilter = .inProgress
        case .inProgress: statusFilter = .completed
        default:          statusFilter = nil
        }
    }

    // MARK: - Mode Segment

    @ViewBuilder
    private func modeTabBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.sweeplySurface)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.sweeplyAccent.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var modeSegment: some View {
        HStack(spacing: 4) {
            ForEach(CleanerScheduleMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode = mode }
                } label: {
                    let isSelected = viewMode == mode
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(modeTabBackground(isSelected: isSelected))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.sweeplySurface)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    // MARK: - Stats Bar

    private func statsBar(jobs: [Job]) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(jobs.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyAccent)
                Text(jobs.count == 1 ? "job" : "jobs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Text(jobs.reduce(0) { $0 + $1.price }.currency)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.sweeplySurface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.sweeplyBorder), alignment: .bottom)
    }

    // MARK: - Day View (Timeline)

    private var dayView: some View {
        VStack(spacing: 0) {
            statsBar(jobs: filteredJobsForDay)

            ScrollView {
                if jobsStore.isLoading && jobsStore.jobs.isEmpty {
                    SkeletonList(count: 4).padding(.top, 16).padding(.horizontal, 20)
                } else if filteredJobsForDay.isEmpty {
                    emptyState
                } else {
                    let hours = Array(timelineStartHour...timelineEndHour)
                    let totalHeight = CGFloat(hours.count) * timelineHourHeight

                    ZStack(alignment: .topLeading) {
                        // Hour grid rows
                        VStack(spacing: 0) {
                            ForEach(hours, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(timelineHourLabel(hour))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.55))
                                        .frame(width: 44, alignment: .trailing)
                                        .padding(.top, -5)
                                    Rectangle()
                                        .fill(Color.sweeplyBorder.opacity(0.45))
                                        .frame(height: 0.5)
                                        .padding(.leading, 10)
                                        .padding(.top, 1)
                                }
                                .frame(height: timelineHourHeight, alignment: .top)
                            }
                        }

                        // Current time indicator (today only)
                        if calendar.isDateInToday(selectedDay) {
                            let now = Date()
                            let nowHour = Calendar.current.component(.hour, from: now)
                            let nowMinute = Calendar.current.component(.minute, from: now)
                            let yNow = CGFloat(nowHour - timelineStartHour) * timelineHourHeight
                                     + CGFloat(nowMinute) / 60.0 * timelineHourHeight
                            HStack(spacing: 0) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .padding(.leading, 40)
                                Rectangle()
                                    .fill(Color.red.opacity(0.7))
                                    .frame(height: 1.5)
                            }
                            .offset(y: max(0, yNow) + timelineHourHeight * 0.5)
                        }

                        // Job blocks
                        ForEach(filteredJobsForDay) { job in
                            let jobHour = Calendar.current.component(.hour, from: job.date)
                            let jobMinute = Calendar.current.component(.minute, from: job.date)
                            let yOffset = CGFloat(jobHour - timelineStartHour) * timelineHourHeight
                                        + CGFloat(jobMinute) / 60.0 * timelineHourHeight
                            let blockHeight = max(CGFloat(job.duration) * timelineHourHeight, 56)
                            CleanerTimelineJobBlock(job: job) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedJobId = job.id
                            }
                            .frame(height: blockHeight)
                            .padding(.leading, 58)
                            .offset(y: max(0, yOffset))
                        }
                    }
                    .frame(height: totalHeight)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.bottom, 100)
                }
            }
            .refreshable {
                await jobsStore.load(isAuthenticated: session.isAuthenticated)
            }
        }
    }

    private func timelineHourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }

    // MARK: - List View (Agenda)

    private func agendaDateLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var listView: some View {
        VStack(spacing: 0) {
            let allUpcoming = upcomingGroupedJobs.flatMap { $0.jobs }
            statsBar(jobs: allUpcoming)

            ScrollView {
                if jobsStore.isLoading && jobsStore.jobs.isEmpty {
                    SkeletonList(count: 4).padding(.top, 16).padding(.horizontal, 20)
                } else if upcomingGroupedJobs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                        Text("No upcoming jobs")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(statusFilter != nil ? "Try clearing the filter." : "Nothing scheduled yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(upcomingGroupedJobs, id: \.date) { group in
                            Section {
                                VStack(spacing: 8) {
                                    ForEach(group.jobs) { job in
                                        CleanerListJobRow(job: job) {
                                            selectedJobId = job.id
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                            } header: {
                                HStack(spacing: 8) {
                                    Text(agendaDateLabel(group.date))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(calendar.isDateInToday(group.date) ? Color.sweeplyAccent : Color.sweeplyNavy)
                                    Text("·")
                                        .foregroundStyle(Color.sweeplyBorder)
                                    Text(group.jobs.reduce(0) { $0 + $1.price }.currency)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                    Spacer()
                                    Text("\(group.jobs.count) job\(group.jobs.count == 1 ? "" : "s")")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.sweeplyBackground)
                                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.sweeplyBorder.opacity(0.5)), alignment: .bottom)
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .refreshable {
                await jobsStore.load(isAuthenticated: session.isAuthenticated)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
            Text("No jobs this day")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(statusFilter != nil ? "Try clearing the filter." : "Enjoy your day off.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - CleanerTimelineJobBlock

private struct CleanerTimelineJobBlock: View {
    let job: Job
    let onTap: () -> Void

    private var accentColor: Color {
        switch job.serviceType {
        case .standard:         return Color.sweeplyAccent
        case .deep:             return Color.sweeplyNavy
        case .moveInOut:        return Color.sweeplyWarning
        case .postConstruction: return Color.gray
        case .office:           return Color.sweeplyNavy
        case .custom:           return Color.sweeplyAccent
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accentColor.opacity(0.25), lineWidth: 1)
                    )
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 4)
                        .padding(.vertical, 8)
                        .padding(.leading, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.clientName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineLimit(1)
                        Text(job.serviceType.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(timeString(from: job.date))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text("·")
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                            Text(job.price.currency)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 8)
                    Spacer()
                    StatusBadge(status: job.status)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - CleanerListJobRow

private struct CleanerListJobRow: View {
    let job: Job
    let onTap: () -> Void

    @State private var isPressed = false

    private var accentColor: Color {
        switch job.serviceType {
        case .standard:         return Color.sweeplyAccent
        case .deep:             return Color.sweeplyNavy
        case .moveInOut:        return Color.sweeplyWarning
        case .postConstruction: return Color.gray
        case .office:           return Color.sweeplyNavy
        case .custom:           return Color.sweeplyAccent
        }
    }

    private var durationLabel: String {
        let d = job.duration
        if d <= 0 { return "" }
        if d == d.rounded() { return "\(Int(d))h" }
        return String(format: "%.1fh", d)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                Color.sweeplySurface

                Capsule()
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 0)

                HStack(spacing: 14) {
                    Color.clear.frame(width: 3)

                    VStack(alignment: .leading, spacing: 6) {
                        // Row 1: client + duration pill + price
                        HStack(spacing: 4) {
                            Text(job.clientName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            if !durationLabel.isEmpty {
                                Text(durationLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            Text(job.price.currency)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }

                        // Row 2: clock + time
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                            Text(timeString(from: job.date))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }

                        // Row 3: service pill + status badge
                        HStack(spacing: 8) {
                            Text(job.serviceType.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            StatusBadge(status: job.status)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyBorder)
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - CleanerMonthPicker

private struct CleanerMonthPicker: View {
    @Binding var selectedDay: Date
    let jobs: [Job]
    @Environment(\.dismiss) private var dismiss
    @State private var hasInteracted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(monthYearTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDay = Calendar.current.startOfDay(for: Date())
                    }
                    dismiss()
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.sweeplyAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            JobberCalendarView(selectedDay: $selectedDay, jobs: jobs)
                .padding(.horizontal, 20)

            Spacer(minLength: 12)

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .onChange(of: selectedDay) { _, _ in
            guard hasInteracted else { hasInteracted = true; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
        }
        .onAppear { hasInteracted = false }
    }

    private var monthYearTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDay)
    }
}
