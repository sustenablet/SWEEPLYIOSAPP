import SwiftUI
import MapKit

// MARK: - Schedule (Jobber-style day / list / map / map)

enum ScheduleViewMode: String, CaseIterable {
    case day = "Day"
    case list = "List"
    case month = "Month"
    case map = "Map"
}

struct ScheduleView: View {
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore
    @State private var appeared = false
    @State private var viewMode: ScheduleViewMode = .day
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showFilters = false
    @State private var statusFilter: JobStatus? = nil
    @State private var typeFilter: String = "All"
    @State private var showMonthPicker = false
    @State private var enabledViewModes: Set<ScheduleViewMode> = [.day, .list, .month, .map]
    
    private var visibleViewModes: [ScheduleViewMode] {
        ScheduleViewMode.allCases.filter { enabledViewModes.contains($0) }
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topToolbar
                modeSegment
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                if viewMode == .day {
                    weekStrip
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                Group {
                    switch viewMode {
                    case .day:   dayView
                    case .list:  listView
                    case .month: monthView
                    case .map:   mapView
                    }
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showFilters) {
                JobFiltersView(statusFilter: $statusFilter, typeFilter: $typeFilter, enabledViewModes: $enabledViewModes)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showMonthPicker) {
                ScheduleMonthPicker(selectedDay: $selectedDay)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: Top toolbar (month + icons)

    private var topToolbar: some View {
        PageHeader(
            eyebrow: nil,
            title: "Schedule",
            subtitle: monthTitle
        ) {
            HStack(spacing: 4) {
                HeaderIconButton(systemName: "calendar") {
                    showMonthPicker = true
                }
                HeaderIconButton(systemName: "line.3.horizontal.decrease.circle") {
                    showFilters = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: selectedDay)
    }

    // MARK: Day / List / Map segment

    private var modeSegment: some View {
        HStack(spacing: 4) {
            ForEach(visibleViewModes, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: viewMode == mode ? .semibold : .medium))
                        .foregroundStyle(viewMode == mode ? Color.sweeplyNavy : Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if viewMode == mode {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.sweeplySurface)
                                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.93, green: 0.93, blue: 0.94))
        )
    }

    // MARK: - Map View
    
    private var mapView: some View {
        VStack(spacing: 0) {
            if jobsStore.jobs.isEmpty {
                scheduleEmptyState
            } else {
                Map {
                    ForEach(jobsStore.jobs) { job in
                        if let client = clientsStore.clients.first(where: { $0.id == job.clientId }) {
                            Annotation(job.clientName, coordinate: CLLocationCoordinate2D(latitude: client.latitude ?? 0, longitude: client.longitude ?? 0)) {
                                ZStack {
                                    Circle()
                                        .fill(statusColor(for: job.status))
                                        .frame(width: 12, height: 12)
                                    Circle()
                                        .stroke(.white, lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                }
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.school, .park])))
                .ignoresSafeArea(edges: .bottom)
                
                VStack {
                    Spacer()
                    HStack {
                        Text("\(jobsStore.jobs.count) jobs on map")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.sweeplyNavy.opacity(0.9))
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    private func statusColor(for status: JobStatus) -> Color {
        switch status {
        case .completed: return .sweeplyAccent
        case .inProgress: return .blue
        case .scheduled: return .gray
        case .cancelled: return .red
        }
    }

    // MARK: - Day View
    
    private var dayView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { moveDate(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 2) {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 14, weight: .bold))
                    Text(selectedDay.formatted(.dateTime.day().month()))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()
                Button { moveDate(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.sweeplySurface)
            
            HStack {
                Text("\(filteredJobsForDate(selectedDay).count) Jobs")
                Spacer()
                Text("Total: \(dayRevenue(selectedDay).currency)")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.sweeplyTextSub)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 12) {
                    if filteredJobsForDate(selectedDay).isEmpty {
                        scheduleEmptyState
                    } else {
                        ForEach(filteredJobsForDate(selectedDay)) { job in
                            ScheduleJobRow(job: job)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
    }
    
    private func moveDate(by days: Int) {
        selectedDay = calendar.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
    }
    
    private func dayRevenue(_ date: Date) -> Double {
        filteredJobsForDate(date).reduce(0) { $0 + $1.price }
    }

    // MARK: - List View
    
    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let futureJobs = jobsStore.jobs
                    .filter { $0.date >= calendar.startOfDay(for: Date()) }
                    .filter { applyFilters($0) }
                    .sorted { $0.date < $1.date }
                
                let grouped = Dictionary(grouping: futureJobs) { calendar.startOfDay(for: $0.date) }
                let sortedDates = grouped.keys.sorted()
                
                if futureJobs.isEmpty {
                    scheduleEmptyState.padding(.top, 40)
                } else {
                    ForEach(sortedDates, id: \.self) { date in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(date.formatted(.dateTime.month().day().weekday(.wide)))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .padding(.leading, 4)
                            
                            ForEach(grouped[date] ?? []) { job in
                                ScheduleJobRow(job: job)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Month View
    
    private var monthView: some View {
        VStack(spacing: 0) {
            JobberCalendarView(selectedDay: $selectedDay, jobs: jobsStore.jobs)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Jobs for \(selectedDay.formatted(.dateTime.day().month()))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 12) {
                        if filteredJobsForDate(selectedDay).isEmpty {
                            scheduleEmptyState
                        } else {
                            ForEach(filteredJobsForDate(selectedDay)) { job in
                                ScheduleJobRow(job: job)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
    }
}

// MARK: - Custom Calendar Components

struct JobberCalendarView: View {
    @Binding var selectedDay: Date
    let jobs: [Job]
    private let calendar = Calendar.current
    private let daysInWeek = 7
    
    var body: some View {
        VStack(spacing: 20) {
            // Month/Year and Arrows
            HStack {
                Text(monthYearString)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                HStack(spacing: 20) {
                    Button { moveMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    Button { moveMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                }
                .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 10)

            // Days of week labels
            HStack {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: daysInWeek), spacing: 14) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        CalendarDayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDay),
                            isToday: calendar.isDateInToday(date),
                            jobs: jobsForDate(date)
                        )
                        .onTapGesture { selectedDay = date }
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private var monthYearString: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDay)
    }

    private func moveMonth(by months: Int) {
        if let newDate = calendar.date(byAdding: .month, value: months, to: selectedDay) {
            selectedDay = newDate
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: selectedDay),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDay)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let prefix = Array(repeating: nil as Date?, count: weekday - 1)
        let monthDays = monthRange.map { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
        return prefix + monthDays
    }

    private func jobsForDate(_ date: Date) -> [Job] {
        jobs.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let jobs: [Job]
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : (isToday ? Color.sweeplyAccent : Color.sweeplyNavy))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.sweeplyNavy : (isToday ? Color.sweeplyAccent.opacity(0.1) : Color.clear))
                .clipShape(Circle())

            HStack(spacing: 3) {
                ForEach(jobs.prefix(3)) { job in
                    Circle()
                        .fill(statusColor(for: job.status))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 40)
    }

    private func statusColor(for status: JobStatus) -> Color {
        switch status {
        case .completed: return .green
        case .inProgress: return .orange
        case .cancelled: return .red
        case .scheduled: return Color.sweeplyBorder
        }
    }
}

private extension ScheduleView {

    private func filteredJobsForDate(_ date: Date) -> [Job] {
        jobsStore.jobs
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .filter { applyFilters($0) }
            .sorted { $0.date < $1.date }
    }
    
    private func applyFilters(_ job: Job) -> Bool {
        if let status = statusFilter, job.status != status { return false }
        if typeFilter == "Recurring" && !job.isRecurring { return false }
        if typeFilter == "One-time" && job.isRecurring { return false }
        return true
    }

    private var scheduleEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
            Text("Nothing scheduled")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Jobs you add will show up here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: Week strip (green circle selection)

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                jobberDayCell(day)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func jobberDayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let dayNum = calendar.component(.day, from: day)
        let letter = singleLetterWeekday(day)

        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 6) {
                Text(letter)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.sweeplySuccess)
                            .frame(width: 32, height: 32)
                    }
                    Text("\(dayNum)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.sweeplyNavy)
                }
                .frame(height: 34)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func singleLetterWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    private var weekInterval: DateInterval {
        return calendar.dateInterval(of: .weekOfYear, for: selectedDay)
            ?? DateInterval(start: Date(), end: Date())
    }
 
    private var weekDays: [Date] {
        (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: weekInterval.start)
        }
    }
}

// MARK: - Row Components

private struct ScheduleMonthPicker: View {
    @Binding var selectedDay: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                eyebrow: "Jump To",
                title: "Choose Date",
                subtitle: "Move the schedule to another week or month"
            ) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyAccent)
            }

            DatePicker(
                "Selected Date",
                selection: $selectedDay,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            Button("Jump to Today") {
                selectedDay = Calendar.current.startOfDay(for: Date())
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(20)
        .background(Color.sweeplyBackground.ignoresSafeArea())
    }
}

private struct ScheduleJobRow: View {
    let job: Job
    @Environment(JobsStore.self) private var jobsStore
    @State private var showMenu = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationLink(destination: JobDetailView(jobId: job.id)) {
            ZStack(alignment: .leading) {
                Color.sweeplySurface
                
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 4)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.date.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("\(Int(job.duration)) hr")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .frame(width: 65, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(job.clientName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            if job.isRecurring {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.sweeplyAccent)
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text(job.serviceType.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                            
                            StatusBadge(status: job.status)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Text(job.price.currency)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        
                        // Menu Button removed or changed because the whole row is clickable now.
                        // Actually, I can keep the menu button inside if it works, or I'll just keep it.
                        // But wait! Menus inside NavigationLink sometimes steal touches. 
                        // It's safest to just rely on the DetailView!
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.sweeplyBorder)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(JobStatus.allCases, id: \.self) { status in
                if job.status != status {
                    Button("Mark as \(status.rawValue.capitalized)") {
                        Task { await jobsStore.updateStatus(id: job.id, status: status) }
                    }
                }
            }
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .alert("Delete Job?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await jobsStore.delete(id: job.id) }
            }
        } message: {
            Text("Are you sure you want to delete this job?")
        }
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

#Preview {
    ScheduleView()
        .environment(AppSession())
        .environment(JobsStore())
}

