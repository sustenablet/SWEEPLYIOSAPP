import SwiftUI
import MapKit
import CoreLocation

// MARK: - Cleaner Schedule View

enum CleanerScheduleMode: String, CaseIterable {
    case day   = "Day"
    case list  = "List"
    case month = "Month"
    case map   = "Map"
}

struct CleanerUpcomingView: View {
    @Environment(JobsStore.self)    private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self)   private var session

    let membership: TeamMembership

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @AppStorage("cleanerScheduleViewMode")     private var viewModeRaw: String = CleanerScheduleMode.day.rawValue
    @AppStorage("cleanerScheduleStatusFilter") private var statusFilterRaw: String = ""
    @AppStorage("cleanerScheduleTypeFilter")   private var typeFilter: String = "All"
    @AppStorage("cleanerScheduleEnabledModes") private var enabledModesRaw: String = "Day,List,Month,Map"
    @State private var showMonthPicker = false
    @State private var showFilters = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var mapSelectedJobId: UUID? = nil
    @State private var showMapJobDetail = false
    @State private var locationManager = LocationManager.shared

    private var viewMode: CleanerScheduleMode { CleanerScheduleMode(rawValue: viewModeRaw) ?? .day }
    private var statusFilter: JobStatus? { JobStatus(rawValue: statusFilterRaw) }
    private var statusFilterBinding: Binding<JobStatus?> {
        Binding(get: { JobStatus(rawValue: statusFilterRaw) }, set: { statusFilterRaw = $0?.rawValue ?? "" })
    }
    @State private var selectedJobId: UUID? = nil

    private var enabledViewModes: Set<CleanerScheduleMode> {
        let modes = enabledModesRaw.split(separator: ",").compactMap { CleanerScheduleMode(rawValue: String($0)) }
        return modes.isEmpty ? Set(CleanerScheduleMode.allCases) : Set(modes)
    }

    private func setEnabledViewModes(_ modes: Set<CleanerScheduleMode>) {
        enabledModesRaw = modes.map(\.rawValue).joined(separator: ",")
        if !modes.contains(viewMode),
           let first = CleanerScheduleMode.allCases.first(where: { modes.contains($0) }) {
            viewModeRaw = first.rawValue
        }
    }

    private var visibleViewModes: [CleanerScheduleMode] {
        CleanerScheduleMode.allCases.filter { enabledViewModes.contains($0) }
    }

    private let calendar: Calendar = {
        var c = Calendar.current; c.firstWeekday = 1; return c
    }()

    private let timelineHourHeight: CGFloat = 68
    private var timelineStartHour: Int {
        let jobs = filteredJobsForDay
        guard !jobs.isEmpty else { return 6 }
        let earliestHour = Calendar.current.component(.hour, from: jobs.map { $0.date }.min()!)
        return min(max(0, earliestHour - 1), 6)
    }
    private var timelineEndHour: Int {
        let jobs = filteredJobsForDay
        guard !jobs.isEmpty else { return 21 }
        let latestJob = jobs.max { job1, job2 in
            let end1 = job1.date.addingTimeInterval(job1.duration * 3600)
            let end2 = job2.date.addingTimeInterval(job2.duration * 3600)
            return end1 < end2
        }!
        let endTime = latestJob.date.addingTimeInterval(latestJob.duration * 3600)
        let latestHour = Calendar.current.component(.hour, from: endTime)
        return max(latestHour + 1, 21)
    }

    private var hasActiveFilters: Bool {
        statusFilter != nil || typeFilter != "All"
    }

    // MARK: - Derived

    private var myJobs: [Job] {
        jobsStore.jobs.filter { $0.assignedMemberId == membership.id && $0.status != .cancelled }
    }

    private func applyFilters(_ job: Job) -> Bool {
        if let status = statusFilter, job.status != status { return false }
        if typeFilter == "Recurring" && !job.isRecurring { return false }
        if typeFilter == "One-time" && job.isRecurring { return false }
        return true
    }

    private var filteredJobsForDay: [Job] {
        myJobs
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .filter { applyFilters($0) }
            .sorted { $0.date < $1.date }
    }

    private var upcomingGroupedJobs: [(date: Date, jobs: [Job])] {
        let today = calendar.startOfDay(for: Date())
        let upcoming = myJobs
            .filter { calendar.startOfDay(for: $0.date) >= today && applyFilters($0) }
            .sorted { $0.date < $1.date }
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (date: $0.key, jobs: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.date < $1.date }
    }

    // True when the selected day has jobs and every one is completed/cancelled
    private var allJobsDoneForDay: Bool {
        !filteredJobsForDay.isEmpty &&
        filteredJobsForDay.allSatisfy { $0.status == .completed || $0.status == .cancelled }
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

                // Week strip — Day and List only; Month has its own calendar, Map has a date chip
                if viewMode == .day || viewMode == .list {
                    WeekStripView(selectedDay: $selectedDay, jobs: myJobs)
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
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId, ownerId: membership.ownerId)
            }
            .sheet(isPresented: $showMonthPicker) {
                CleanerMonthPicker(selectedDay: $selectedDay, jobs: myJobs)
                    .presentationDetents([.fraction(0.65)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFilters) {
                CleanerJobFiltersView(
                    statusFilter: statusFilterBinding,
                    typeFilter: $typeFilter,
                    enabledViewModes: Binding(
                        get: { enabledViewModes },
                        set: { setEnabledViewModes($0) }
                    )
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showMapJobDetail) {
                if let jobId = mapSelectedJobId {
                    CleanerJobDetailView(jobId: jobId, ownerId: membership.ownerId)
                        .onDisappear { mapSelectedJobId = nil }
                }
            }
            .onChange(of: viewMode) { _, newMode in
                guard newMode == .map else { return }
                updateMapCamera(for: selectedDay)
            }
            .onChange(of: selectedDay) { _, newDay in
                guard viewMode == .map else { return }
                updateMapCamera(for: newDay)
            }
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule".translated())
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

            HeaderIconButton(systemName: hasActiveFilters
                             ? "line.3.horizontal.decrease.circle.fill"
                             : "line.3.horizontal.decrease.circle") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFilters = true
            }
        }
        .frame(minHeight: 76, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.top, 16)
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
            ForEach(visibleViewModes, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModeRaw = mode.rawValue }
                } label: {
                    let isSelected = viewMode == mode
                    Text(mode.rawValue.translated())
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

    // MARK: - Member Pay Day

    private func isMemberPayDay(for date: Date) -> Bool {
        guard membership.payRateEnabled && membership.payRateAmount > 0 else { return false }
        switch membership.payRateType {
        case .perDay:  return true
        case .perWeek:
            let weekday = Calendar.current.component(.weekday, from: date)
            return membership.payDayOfWeek == weekday
        default: return false
        }
    }

    private var memberPaycheckCard: some View {
        let isWeekly = membership.payRateType == .perWeek
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.sweeplySuccess.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.sweeplySuccess)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isWeekly ? "PAYDAY" : "DAILY PAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.sweeplySuccess)
                    .tracking(0.8)
                Text("From \(membership.businessName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            Spacer()
            Text(membership.payRateAmount.currency)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.sweeplySuccess.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplySuccess.opacity(0.25), lineWidth: 1))
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

    // MARK: - Map View

    private var mapView: some View {
        let dayJobs = filteredJobsForDay
        return ZStack(alignment: .bottom) {
            Map(position: $mapCameraPosition) {
                ForEach(dayJobs) { job in
                    if let client = clientsStore.clients.first(where: { $0.id == job.clientId }),
                       let lat = client.latitude, let lng = client.longitude {
                        Annotation(job.clientName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                            MapPinView(
                                status: job.status,
                                isSelected: mapSelectedJobId == job.id
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    mapSelectedJobId = job.id
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

            // Controls overlay
            VStack {
                HStack(alignment: .top) {
                    // Date chip
                    Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.sweeplySurface.opacity(0.95))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)

                    Spacer()

                    VStack(spacing: 12) {
                        MapActionButton(icon: "location.fill") {
                            withAnimation { mapCameraPosition = .userLocation(fallback: .automatic) }
                        }
                        MapActionButton(icon: "building.2.fill") {
                            let coords = dayJobs.compactMap { job -> CLLocationCoordinate2D? in
                                guard let c = clientsStore.clients.first(where: { $0.id == job.clientId }),
                                      let lat = c.latitude, let lon = c.longitude else { return nil }
                                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            }
                            guard !coords.isEmpty else { return }
                            let lats = coords.map(\.latitude)
                            let lons = coords.map(\.longitude)
                            let center = CLLocationCoordinate2D(
                                latitude: (lats.min()! + lats.max()!) / 2,
                                longitude: (lons.min()! + lons.max()!) / 2
                            )
                            let span = MKCoordinateSpan(
                                latitudeDelta: (lats.max()! - lats.min()!) * 1.5 + 0.05,
                                longitudeDelta: (lons.max()! - lons.min()!) * 1.5 + 0.05
                            )
                            withAnimation { mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span)) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
            }

            // Selected job card
            if let jobId = mapSelectedJobId,
               let job = dayJobs.first(where: { $0.id == jobId }) {
                let client = clientsStore.clients.first(where: { $0.id == job.clientId })
                MapJobCard(
                    job: job,
                    client: client,
                    onDirections: { openDirections(for: job) },
                    onDetails: { showMapJobDetail = true },
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            mapSelectedJobId = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
    }

    private func updateMapCamera(for day: Date) {
        let jobs = myJobs.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let coords = jobs.compactMap { job -> CLLocationCoordinate2D? in
            guard let client = clientsStore.clients.first(where: { $0.id == job.clientId }),
                  let lat = client.latitude, let lon = client.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        let userLoc = locationManager.location
        let fallback = CLLocationCoordinate2D(
            latitude: userLoc?.coordinate.latitude ?? 37.3346,
            longitude: userLoc?.coordinate.longitude ?? -122.0090
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            if coords.isEmpty {
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: fallback,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            } else {
                let lats = coords.map(\.latitude)
                let lons = coords.map(\.longitude)
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (lats.min()! + lats.max()!) / 2,
                        longitude: (lons.min()! + lons.max()!) / 2
                    ),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }

    private func openDirections(for job: Job) {
        let lat = clientsStore.clients.first(where: { $0.id == job.clientId })?.latitude ?? 0
        let lon = clientsStore.clients.first(where: { $0.id == job.clientId })?.longitude ?? 0
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        mapItem.name = job.clientName
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    // MARK: - Day View (Timeline)

    private var dayView: some View {
        let jobs = filteredJobsForDay
        let isPayDay = isMemberPayDay(for: selectedDay)
        return VStack(spacing: 0) {
            // Stats bar
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

            ScrollView {
                // Pay day banner — shown at the top when it's the member's pay day
                if isPayDay {
                    memberPaycheckCard
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }

                if jobsStore.isLoading && jobsStore.jobs.isEmpty {
                    SkeletonList(count: 4).padding(.top, 16).padding(.horizontal, 20)
                } else if jobs.isEmpty && !isPayDay {
                    emptyState
                } else if !jobs.isEmpty {
                    let hours = Array(timelineStartHour...timelineEndHour)
                    let totalHeight = CGFloat(hours.count) * timelineHourHeight
                    let assignments = cleanerComputeColumns(jobs)
                    let maxCols = assignments.map(\.totalColumns).max() ?? 1

                    GeometryReader { geo in
                        let labelW: CGFloat = 38
                        let colWidth = geo.size.width - labelW
                        let colGap: CGFloat = 6
                        let scrollW = maxCols > 1
                            ? CGFloat(maxCols) * colWidth + CGFloat(maxCols - 1) * colGap
                            : colWidth

                        HStack(alignment: .top, spacing: 0) {
                            // Pinned hour labels
                            VStack(spacing: 0) {
                                ForEach(hours, id: \.self) { hour in
                                    Text(timelineHourLabel(hour))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.55))
                                        .frame(width: labelW, alignment: .trailing)
                                        .padding(.top, -5)
                                        .frame(height: timelineHourHeight, alignment: .top)
                                }
                            }
                            .frame(width: labelW)

                            // Scrollable job area
                            ScrollView(.horizontal, showsIndicators: false) {
                                ZStack(alignment: .topLeading) {
                                    // Horizontal grid lines
                                    VStack(spacing: 0) {
                                        ForEach(hours, id: \.self) { _ in
                                            Rectangle()
                                                .fill(Color.sweeplyBorder.opacity(0.45))
                                                .frame(height: 0.5)
                                                .padding(.top, 1)
                                                .frame(height: timelineHourHeight, alignment: .top)
                                        }
                                    }

                                    // "Now" indicator
                                    if calendar.isDateInToday(selectedDay) {
                                        let now = Date()
                                        let nowHour = Calendar.current.component(.hour, from: now)
                                        let nowMinute = Calendar.current.component(.minute, from: now)
                                        let yNow = CGFloat(nowHour - timelineStartHour) * timelineHourHeight
                                                 + CGFloat(nowMinute) / 60.0 * timelineHourHeight
                                        HStack(spacing: 0) {
                                            Circle().fill(Color.red).frame(width: 8, height: 8)
                                            Rectangle().fill(Color.red.opacity(0.7)).frame(height: 1.5)
                                        }
                                        .offset(y: max(0, yNow) + timelineHourHeight * 0.5)
                                    }

                                    // Job blocks — side by side when overlapping
                                    ForEach(assignments, id: \.job.id) { item in
                                        let jobHour = Calendar.current.component(.hour, from: item.job.date)
                                        let jobMinute = Calendar.current.component(.minute, from: item.job.date)
                                        let yOffset = CGFloat(jobHour - timelineStartHour) * timelineHourHeight
                                                    + CGFloat(jobMinute) / 60.0 * timelineHourHeight
                                        let blockHeight = max(CGFloat(item.job.duration) * timelineHourHeight, 44)
                                        let xOffset = CGFloat(item.column) * (colWidth + colGap)
                                        CleanerTimelineJobBlock(job: item.job) {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedJobId = item.job.id
                                        }
                                            .frame(width: colWidth - 4, height: blockHeight)
                                            .offset(x: xOffset + 2, y: max(0, yOffset))
                                    }
                                }
                                .frame(width: scrollW, height: totalHeight)
                            }
                            .scrollDisabled(maxCols <= 1)
                        }
                    }
                    .frame(height: totalHeight)
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, 100)
                }
            }
            .refreshable { await jobsStore.load(isAuthenticated: session.isAuthenticated) }
        }
    }

    // MARK: - Cleaner Column Layout

    private func cleanerComputeColumns(_ jobs: [Job]) -> [JobColumnAssignment] {
        var assignments: [JobColumnAssignment] = []
        var columnsByStartMinute: [Int: Int] = [:]

        for job in jobs.sorted(by: { $0.date < $1.date }) {
            let startMinute = Calendar.current.component(.hour, from: job.date) * 60 + Calendar.current.component(.minute, from: job.date)
            let endMinute = startMinute + Int(job.duration * 60)

            var column = 0
            while columnsByStartMinute[column] ?? 0 > startMinute {
                column += 1
            }

            assignments.append(JobColumnAssignment(job: job, column: column, totalColumns: column + 1))

            columnsByStartMinute[column] = endMinute
        }

        return assignments
    }

    private struct JobColumnAssignment: Identifiable {
        let job: Job
        let column: Int
        let totalColumns: Int
        var id: UUID { job.id }
    }

    private func timelineHourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return "\(h)\(suffix)"
    }

    // MARK: - List View (Agenda)

    private func agendaDateLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today".translated() }
        if calendar.isDateInTomorrow(date) { return "Tomorrow".translated() }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var listView: some View {
        VStack(spacing: 0) {
            statsBar(jobs: filteredJobsForDay)

            ScrollView {
                if isMemberPayDay(for: selectedDay) {
                    memberPaycheckCard
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }

                if jobsStore.isLoading && jobsStore.jobs.isEmpty {
                    SkeletonList(count: 4).padding(.top, 16).padding(.horizontal, 20)
                } else if allJobsDoneForDay {
                    allDoneState
                } else if filteredJobsForDay.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredJobsForDay) { job in
                            CleanerListJobRow(job: job) { selectedJobId = job.id }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
            .refreshable { await jobsStore.load(isAuthenticated: session.isAuthenticated) }
        }
    }

    // MARK: - Month View

    private var monthView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                JobberCalendarView(selectedDay: $selectedDay, jobs: myJobs)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Text("Jobs for \(selectedDay.formatted(.dateTime.day().month(.wide)))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                if filteredJobsForDay.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                        Text("No jobs this day".translated())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(hasActiveFilters ? "Try adjusting your filters." : "Nothing scheduled.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredJobsForDay) { job in
                            CleanerListJobRow(job: job) { selectedJobId = job.id }
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable { await jobsStore.load(isAuthenticated: session.isAuthenticated) }
    }

    // MARK: - Empty State

    private var allDoneState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            VStack(spacing: 6) {
                Text(calendar.isDateInToday(selectedDay) ? "All done for today!" : "All jobs complete!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(calendar.isDateInToday(selectedDay)
                     ? "Great work — you've wrapped up everything on your schedule."
                     : "Every job on this day was completed.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            // Show a summary of what was completed
            let completedCount = filteredJobsForDay.filter { $0.status == .completed }.count
            if completedCount > 0 {
                Text("\(completedCount) job\(completedCount == 1 ? "" : "s") completed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.sweeplyAccent.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
            Text(hasActiveFilters ? "No matching jobs" : "No jobs this day")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(hasActiveFilters ? "Try adjusting your filters." : "Enjoy your day off.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Cleaner Job Filters Sheet

private struct CleanerJobFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var statusFilter: JobStatus?
    @Binding var typeFilter: String
    @Binding var enabledViewModes: Set<CleanerScheduleMode>

    @State private var localStatus: JobStatus?
    @State private var localType: String = "All"
    @State private var localViewModes: Set<CleanerScheduleMode> = Set(CleanerScheduleMode.allCases)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filters".translated())
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 32, height: 32)
                        .background(Color.sweeplyBorder.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Status filter
                    VStack(alignment: .leading, spacing: 16) {
                        FilterHeader(title: "JOB STATUS", subtitle: "Filter by current job progress".translated())
                        ChipGroup(spacing: 8) {
                            FilterChip(label: "All Statuses", isSelected: localStatus == nil) {
                                localStatus = nil
                            }
                            ForEach(JobStatus.allCases, id: \.self) { status in
                                FilterChip(
                                    label: status.rawValue,
                                    isSelected: localStatus == status,
                                    color: statusColor(for: status)
                                ) { localStatus = status }
                            }
                        }
                    }

                    // Job type filter
                    VStack(alignment: .leading, spacing: 16) {
                        FilterHeader(title: "SCHEDULE TYPE", subtitle: "One-time or recurring jobs".translated())
                        HStack(spacing: 12) {
                            TypeCard(label: "All", icon: "square.grid.2x2.fill", isSelected: localType == "All") {
                                localType = "All"
                            }
                            TypeCard(label: "Recurring", icon: "arrow.triangle.2.circlepath", isSelected: localType == "Recurring") {
                                localType = "Recurring"
                            }
                            TypeCard(label: "One-time", icon: "calendar", isSelected: localType == "One-time") {
                                localType = "One-time"
                            }
                        }
                    }

                    // View mode toggles
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("VIEW OPTIONS".translated())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .tracking(1.0)
                            Text("Select which tabs appear in the schedule".translated())
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }

                        VStack(spacing: 1) {
                            ForEach(CleanerScheduleMode.allCases, id: \.self) { mode in
                                ToggleRow(
                                    label: mode.rawValue,
                                    icon: iconFor(mode: mode),
                                    isOn: localViewModes.contains(mode)
                                ) {
                                    if localViewModes.contains(mode) {
                                        if localViewModes.count > 1 { localViewModes.remove(mode) }
                                    } else {
                                        localViewModes.insert(mode)
                                    }
                                }
                                if mode != CleanerScheduleMode.allCases.last {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color.sweeplyBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }

            // Footer
            VStack(spacing: 12) {
                Button {
                    statusFilter = localStatus
                    typeFilter = localType
                    enabledViewModes = localViewModes
                    dismiss()
                } label: {
                    Text("Apply Changes".translated())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                Button("Cancel".translated()) { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .padding(.bottom, 8)
            }
            .padding(24)
            .background(Color.sweeplySurface)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
        }
        .background(Color.sweeplySurface)
        .onAppear {
            localStatus = statusFilter
            localType = typeFilter
            localViewModes = enabledViewModes
        }
    }

    private func iconFor(mode: CleanerScheduleMode) -> String {
        switch mode {
        case .day:   return "calendar.badge.clock"
        case .list:  return "list.bullet"
        case .month: return "calendar"
        case .map:   return "map.fill"
        }
    }

    private func statusColor(for status: JobStatus) -> Color {
        switch status {
        case .completed:  return Color.sweeplyAccent
        case .inProgress: return .blue
        case .scheduled:  return Color.sweeplyNavy
        case .cancelled:  return Color.sweeplyDestructive
        }
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
                        Text(job.serviceType.rawValue.translated())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(timeString(from: job.date))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text("·").foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                            Text(job.price.currency)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 8)
                    Spacer()
                    StatusBadge(status: job.status).padding(.trailing, 10)
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
                HStack(spacing: 14) {
                    Color.clear.frame(width: 3)
                    VStack(alignment: .leading, spacing: 6) {
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
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                            Text(timeString(from: job.date))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        HStack(spacing: 8) {
                            Text(job.serviceType.rawValue.translated())
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
                .onEnded   { _ in isPressed = false }
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
                    Text("Today".translated())
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
                Text("Done".translated())
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
