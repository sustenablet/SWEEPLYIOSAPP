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
    @Environment(AppSession.self) private var session
    @State private var appeared = false
    @State private var viewMode: ScheduleViewMode = .day
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showFilters = false
    @State private var statusFilter: JobStatus? = nil
    @State private var typeFilter: String = "All"
    @State private var showMonthPicker = false
    @State private var enabledViewModes: Set<ScheduleViewMode> = [.day, .list, .map]
    @State private var selectedJobId: UUID? = nil
    @Namespace private var mapSelectionNamespace
    
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
                    dateStrip
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
                    .presentationDetents([.large])
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
        ZStack(alignment: .bottom) {
            Map(initialPosition: MapCameraPosition.automatic) {
                ForEach(jobsStore.jobs) { job in
                    if let client = clientsStore.clients.first(where: { $0.id == job.clientId }) {
                        Annotation(job.clientName, coordinate: CLLocationCoordinate2D(latitude: client.latitude ?? 0, longitude: client.longitude ?? 0)) {
                            MapPinView(
                                status: job.status,
                                isSelected: selectedJobId == job.id,
                                serviceType: job.serviceType
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedJobId = job.id
                                }
                            }
                        }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.school, .park, .hospital])))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            
            // Map Controls Overlay
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        MapActionButton(icon: "location.fill") {
                            // In a real app, this would use MapProxy to center on user
                        }
                        MapActionButton(icon: "scope") {
                            // Recenter on all jobs
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 120)
                }
                Spacer()
            }
            
            // Selected Job Card
            if let selectedJobId = selectedJobId,
               let job = jobsStore.jobs.first(where: { $0.id == selectedJobId }) {
                MapJobCard(
                    job: job,
                    onDirections: { openDirections(for: job) },
                    onDetails: { /* Navigation handled via state or proxy if needed */ },
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            self.selectedJobId = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
            
            if jobsStore.jobs.isEmpty {
                scheduleEmptyState
                    .background(Color.sweeplyBackground.opacity(0.8))
            }
        }
    }
    
    private func openDirections(for job: Job) {
        let lat = clientsStore.clients.first(where: { $0.id == job.clientId })?.latitude ?? 0
        let lon = clientsStore.clients.first(where: { $0.id == job.clientId })?.longitude ?? 0
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = job.clientName
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
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
            .refreshable {
                await jobsStore.load(isAuthenticated: session.isAuthenticated)
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
        .refreshable {
            await jobsStore.load(isAuthenticated: session.isAuthenticated)
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
                .refreshable {
                    await jobsStore.load(isAuthenticated: session.isAuthenticated)
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

    // MARK: Date strip (14-day horizontal scrollable)

    private var dateStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<14) { offset in
                        let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
                        let isSelected = Calendar.current.isDate(selectedDay, inSameDayAs: date)
                        let isToday = offset == 0
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedDay = date }
                        } label: {
                            VStack(spacing: 4) {
                                Text(dayLabel(for: date))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(dayNumber(for: date))
                                    .font(.system(size: 16, weight: .bold))
                                let jobCount = jobsStore.jobs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.count
                                if jobCount > 0 {
                                    Circle()
                                        .fill(isSelected ? Color.white.opacity(0.6) : Color.sweeplyAccent)
                                        .frame(width: 5, height: 5)
                                } else {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(width: 44, height: 58)
                            .background(isSelected ? Color.sweeplyNavy : (isToday ? Color.sweeplyAccent.opacity(0.08) : Color.sweeplySurface))
                            .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isToday && !isSelected ? Color.sweeplyAccent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(0, anchor: .leading) }
        }
    }

    private func dayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNumber(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }
}

// MARK: - Row Components

private struct ScheduleMonthPicker: View {
    @Binding var selectedDay: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
                
                Spacer()
                
                Text("Choose Date")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                
                Spacer()
                
                Button("Today") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDay = Calendar.current.startOfDay(for: Date())
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyAccent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color.sweeplySurface)
            
            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    DatePicker(
                        "Selected Date",
                        selection: $selectedDay,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Color.sweeplyAccent)
                    .labelsHidden()
                    .padding(16)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
    }
}

private struct ScheduleJobRow: View {
    let job: Job
    @Environment(JobsStore.self) private var jobsStore
    @State private var showMenu = false
    @State private var showDeleteConfirm = false
    @State private var showInvoicePrompt = false
    @State private var showInvoiceSheet = false

    var body: some View {
        NavigationLink(destination: JobDetailView(jobId: job.id)) {
            ZStack(alignment: .leading) {
                Color.sweeplySurface

                // Left accent bar
                Capsule()
                    .fill(Color.sweeplyAccent)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 0)

                HStack(spacing: 14) {
                    // Leading spacer for the accent bar
                    Color.clear.frame(width: 3)

                    // Main content
                    VStack(alignment: .leading, spacing: 6) {
                        // Row 1: client name + recurring icon
                        HStack(spacing: 4) {
                            Text(job.clientName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            if job.isRecurring {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.sweeplyAccent)
                            }
                            Spacer()
                            // Price — right-aligned, monospaced
                            Text(job.price.currency)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }

                        // Row 2: time + duration
                        HStack(spacing: 6) {
                            Text(timeString(from: job.date))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                            Text("\(Int(job.duration)) hr")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }

                        // Row 3: service type pill + status dot + status badge
                        HStack(spacing: 8) {
                            // Service type pill
                            Text(job.serviceType.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sweeplyAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.sweeplyAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            // Status dot + badge
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusDotColor)
                                    .frame(width: 6, height: 6)
                                StatusBadge(status: job.status)
                            }
                        }
                    }

                    // Chevron
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(JobStatus.allCases, id: \.self) { status in
                if job.status != status {
                    Button("Mark as \(status.rawValue)") {
                        if status == .completed {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } else {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        Task { await jobsStore.updateStatus(id: job.id, status: status) }
                        if status == .completed { showInvoicePrompt = true }
                    }
                }
            }
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .alert("Delete Job?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                Task { await jobsStore.delete(id: job.id) }
            }
        } message: {
            Text("Are you sure you want to delete this job?")
        }
        .alert("Create Invoice?", isPresented: $showInvoicePrompt) {
            Button("Not Now", role: .cancel) {}
            Button("Create Invoice") { showInvoiceSheet = true }
        } message: {
            Text("Generate an invoice for \(job.clientName) — \(job.price.currency)?")
        }
        .sheet(isPresented: $showInvoiceSheet) {
            NewInvoiceView(prefill: job)
        }
    }

    private var statusDotColor: Color {
        switch job.status {
        case .completed: return Color.sweeplySuccess
        case .inProgress: return Color.sweeplyWarning
        case .scheduled: return Color.sweeplyTextSub
        case .cancelled: return Color.sweeplyDestructive
        }
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Map Helper Views

struct MapPinView: View {
    let status: JobStatus
    let isSelected: Bool
    let serviceType: ServiceType
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.sweeplyNavy : statusColor)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                Image(systemName: serviceIcon)
                    .font(.system(size: isSelected ? 18 : 14, weight: .bold))
                    .foregroundStyle(.white)
                
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: isSelected ? 48 : 40, height: isSelected ? 48 : 40)
            }
            
            Image(systemName: "triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(180))
                .foregroundStyle(isSelected ? Color.sweeplyNavy : statusColor)
                .offset(y: -4)
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    private var statusColor: Color {
        switch status {
        case .completed: return Color.sweeplyAccent
        case .inProgress: return .blue
        case .scheduled: return Color.sweeplyNavy.opacity(0.6)
        case .cancelled: return Color.sweeplyDestructive
        }
    }
    
    private var serviceIcon: String {
        switch serviceType {
        case .standard: return "house.fill"
        case .deep: return "sparkles"
        case .moveInOut: return "shippingbox.fill"
        case .postConstruction: return "hammer.fill"
        case .office: return "building.2.fill"
        case .custom: return "star.fill"
        }
    }
}

struct MapActionButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.sweeplySurface)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                )
        }
        .buttonStyle(.plain)
    }
}


#Preview {
    ScheduleView()
        .environment(AppSession())
        .environment(JobsStore())
}

