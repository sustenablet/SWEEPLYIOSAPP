import SwiftUI
import MapKit
import CoreLocation

// MARK: - Schedule (Jobber-style day / list / map / map)

enum ScheduleViewMode: String, CaseIterable {
    case day = "Day"
    case list = "List"
    case month = "Month"
    case map = "Map"
}

private let inProgressColor = Color(red: 0.4, green: 0.45, blue: 0.95)

struct ScheduleView: View {
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(TeamStore.self) private var teamStore
    @Environment(AppSession.self) private var session
    @State private var appeared = false
    @AppStorage("scheduleViewModeRaw") private var viewModeRaw: String = ScheduleViewMode.day.rawValue
    @AppStorage("scheduleEnabledModes") private var enabledModesRaw: String = "Day,List"

    private var viewMode: ScheduleViewMode {
        get { ScheduleViewMode(rawValue: viewModeRaw) ?? .day }
        set { viewModeRaw = newValue.rawValue }
    }

    private var enabledViewModes: Set<ScheduleViewMode> {
        get {
            let modes = enabledModesRaw.split(separator: ",").compactMap { ScheduleViewMode(rawValue: String($0)) }
            return modes.isEmpty ? [.day, .list] : Set(modes)
        }
    }

    private func setEnabledViewModes(_ modes: Set<ScheduleViewMode>) {
        enabledModesRaw = modes.map(\.rawValue).joined(separator: ",")
        // If current view mode was removed, switch to first available
        if !modes.contains(viewMode), let first = ScheduleViewMode.allCases.first(where: { modes.contains($0) }) {
            viewModeRaw = first.rawValue
        }
    }

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showFilters = false
    @AppStorage("scheduleShowInvoices")   private var showInvoices: Bool = false
    @AppStorage("scheduleTypeFilter")     private var typeFilter: String = "All"
    @AppStorage("scheduleStatusFilterRaw") private var statusFilterRaw: String = ""

    private var statusFilter: JobStatus? {
        get { JobStatus(rawValue: statusFilterRaw) }
        set { statusFilterRaw = newValue?.rawValue ?? "" }
    }

    private var statusFilterBinding: Binding<JobStatus?> {
        Binding(get: { JobStatus(rawValue: statusFilterRaw) }, set: { statusFilterRaw = $0?.rawValue ?? "" })
    }
    @State private var showMonthPicker = false
    @State private var selectedJobId: UUID? = nil
    @State private var showJobDetail: Bool = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var locationManager = LocationManager.shared
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

                if viewMode != .month {
                    WeekStripView(selectedDay: $selectedDay, jobs: ownJobs)
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToScheduleDate"))) { notification in
                if let date = notification.userInfo?["date"] as? Date {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedDay = Calendar.current.startOfDay(for: date)
                        viewModeRaw = ScheduleViewMode.day.rawValue
                    }
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
            .sheet(isPresented: $showFilters) {
                JobFiltersView(statusFilter: statusFilterBinding, typeFilter: $typeFilter, enabledViewModes: Binding(get: { enabledViewModes }, set: { setEnabledViewModes($0) }), showInvoices: $showInvoices)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showMonthPicker) {
                ScheduleMonthPicker(selectedDay: $selectedDay, jobs: ownJobs)
                    .presentationDetents([.fraction(0.65)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showJobDetail) {
                if let jobId = selectedJobId,
                   let job = jobsStore.jobs.first(where: { $0.id == jobId }) {
                    JobDetailView(jobId: job.id)
                        .onDisappear {
                            selectedJobId = nil
                        }
                }
            }
        }
    }

    // MARK: Top toolbar (month + icons)

    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule".translated())
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)

                Button {
                    showMonthPicker = true
                } label: {
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

            HeaderIconButton(systemName: "line.3.horizontal.decrease.circle") {
                showFilters = true
            }
        }
        .frame(minHeight: 76, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDay)
    }

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

    // MARK: Day / List / Map segment

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

    // MARK: - Map View

    private var mapView: some View {
        let dayJobs = filteredJobsForDate(selectedDay)
        return ZStack(alignment: .bottom) {
            Map(position: $mapCameraPosition) {
                ForEach(dayJobs) { job in
                    if let client = clientsStore.clients.first(where: { $0.id == job.clientId }),
                       let lat = client.latitude, let lng = client.longitude {
                        Annotation(job.clientName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                            MapPinView(
                                status: job.status,
                                isSelected: selectedJobId == job.id
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
            .onChange(of: locationManager.location) { _, newLocation in
                guard viewMode == .map, let newLocation else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    mapCameraPosition = .region(MKCoordinateRegion(
                        center: newLocation.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
                    ))
                }
            }

            // Map Controls Overlay
            VStack {
                HStack(alignment: .top) {
                    // Date chip — shows which day's pins are visible
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
                            withAnimation {
                                mapCameraPosition = .userLocation(fallback: .automatic)
                            }
                        }
                        MapActionButton(icon: "scope") {
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
                            withAnimation {
                                mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
            }

            // Job Card Carousel — appears after a pin is tapped, swipeable
            if selectedJobId != nil {
                let carouselJobs = dayJobs.filter { job in
                    clientsStore.clients.first(where: { $0.id == job.clientId })?.latitude != nil
                }
                if !carouselJobs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(carouselJobs) { job in
                                if let client = clientsStore.clients.first(where: { $0.id == job.clientId }) {
                                    MapJobCard(
                                        job: job,
                                        client: client,
                                        onDirections: { openDirections(for: job) },
                                        onDetails: {
                                            self.selectedJobId = job.id
                                            self.showJobDetail = true
                                        },
                                        onDismiss: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                                self.selectedJobId = nil
                                            }
                                        }
                                    )
                                    .frame(width: UIScreen.main.bounds.width - 48)
                                    .id(job.id)
                                }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 24)
                    }
                    .scrollPosition(id: $selectedJobId)
                    .scrollTargetBehavior(.viewAligned)
                    .padding(.bottom, 90)
                    .onChange(of: selectedJobId) { _, newId in
                        guard let newId,
                              let job = carouselJobs.first(where: { $0.id == newId }),
                              let client = clientsStore.clients.first(where: { $0.id == job.clientId }),
                              let lat = client.latitude, let lon = client.longitude else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            mapCameraPosition = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                            ))
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
        }
    }
    
    private func updateMapCamera(for day: Date) {
        let center = locationManager.location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
        withAnimation(.easeInOut(duration: 0.4)) {
            mapCameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
            ))
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
        case .inProgress: return inProgressColor
        case .scheduled: return .gray
        case .cancelled: return Color.sweeplyDestructive
        }
    }

    // MARK: - Day View (Timeline)

    private let timelineHourHeight: CGFloat = 56
    private var timelineStartHour: Int {
        let jobs = filteredJobsForDate(selectedDay)
        guard !jobs.isEmpty else { return 6 }
        let earliestHour = Calendar.current.component(.hour, from: jobs.map { $0.date }.min()!)
        return min(max(0, earliestHour - 1), 6)  // Earlier of: 1hr buffer OR 6am minimum
    }
    private var timelineEndHour: Int {
        let jobs = filteredJobsForDate(selectedDay)
        guard !jobs.isEmpty else { return 21 }
        // Calculate end hour based on latest job + its duration
        let latestJob = jobs.max { job1, job2 in
            let end1 = job1.date.addingTimeInterval(job1.duration * 3600)
            let end2 = job2.date.addingTimeInterval(job2.duration * 3600)
            return end1 < end2
        }!
        let endTime = latestJob.date.addingTimeInterval(latestJob.duration * 3600)
        let latestHour = Calendar.current.component(.hour, from: endTime)
        return max(latestHour + 1, 21)  // Later of: 1hr buffer OR 9pm minimum
    }

    private var dayView: some View {
        let jobs = filteredJobsForDate(selectedDay)
        let paychecks = paycheckMembers(for: selectedDay)
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
                Text(dayRevenue(selectedDay).currency)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.sweeplySurface)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.sweeplyBorder), alignment: .bottom)

            ScrollView {
                // Paycheck cards — shown before timeline
                if !paychecks.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(paychecks, id: \.id) { member in
                            paycheckCard(for: member)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                }

                if jobsStore.isLoading && jobsStore.jobs.isEmpty {
                    SkeletonList(count: 4).padding(.top, 16).padding(.horizontal, 20)
                } else if jobs.isEmpty && paychecks.isEmpty {
                    scheduleEmptyState
                } else if !jobs.isEmpty {
                    let hours = Array(timelineStartHour...timelineEndHour)
                    let totalHeight = CGFloat(hours.count) * timelineHourHeight
                    let assignments = computeColumns(jobs)
                    let maxCols = assignments.map(\.totalColumns).max() ?? 1

                    GeometryReader { geo in
                        let labelW: CGFloat = 38         // width of the pinned hour labels column
                        let colWidth = geo.size.width - labelW
                        let colGap: CGFloat = 6
                        let scrollW = maxCols > 1
                            ? CGFloat(maxCols) * colWidth + CGFloat(maxCols - 1) * colGap
                            : colWidth

                        HStack(alignment: .top, spacing: 0) {

                            // ── Pinned hour labels (never scroll) ──────────────
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

                            // ── Scrollable job area ────────────────────────────
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
                                        let nowHour   = Calendar.current.component(.hour, from: now)
                                        let nowMinute = Calendar.current.component(.minute, from: now)
                                        let yNow = CGFloat(nowHour - self.timelineStartHour) * timelineHourHeight
                                                 + CGFloat(nowMinute) / 60.0 * timelineHourHeight
                                        HStack(spacing: 0) {
                                            Circle().fill(Color.red).frame(width: 8, height: 8)
                                            Rectangle().fill(Color.red.opacity(0.7)).frame(height: 1.5)
                                        }
                                        .offset(y: max(0, yNow) + timelineHourHeight * 0.5)
                                    }

                                    // Job blocks — side by side when overlapping
                                    ForEach(assignments, id: \.job.id) { item in
                                        let jobHour   = Calendar.current.component(.hour, from: item.job.date)
                                        let jobMinute = Calendar.current.component(.minute, from: item.job.date)
                                        let yOffset     = CGFloat(jobHour - timelineStartHour) * timelineHourHeight
                                                        + CGFloat(jobMinute) / 60.0 * timelineHourHeight
                                        let blockHeight = max(CGFloat(item.job.duration) * timelineHourHeight, 44)
                                        let xOffset     = CGFloat(item.column) * (colWidth + colGap)
                                        TimelineJobBlock(job: item.job)
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
            .refreshable {
                await jobsStore.load(isAuthenticated: session.isAuthenticated)
            }
        }
    }

    private func timelineHourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return "\(h)\(suffix)"
    }

    private func dayRevenue(_ date: Date) -> Double {
        filteredJobsForDate(date).reduce(0) { $0 + $1.price }
    }

    // MARK: - List View (Single Day Focus)

    private var listJobsForSelectedDay: [Job] {
        ownJobs
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .filter { applyFilters($0) }
            .sorted { $0.date < $1.date }
    }

    private func agendaDateLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today".translated() }
        if calendar.isDateInTomorrow(date) { return "Tomorrow".translated() }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var listView: some View {
        let paychecks = paycheckMembers(for: selectedDay)
        let dayInvoices = invoicesForDate(selectedDay)
        let hasJobs = !listJobsForSelectedDay.isEmpty
        let hasInvoices = !dayInvoices.isEmpty
        let hasPaychecks = !paychecks.isEmpty

        return VStack(spacing: 0) {
            // Stats bar
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("\(listJobsForSelectedDay.count)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyAccent)
                    Text(listJobsForSelectedDay.count == 1 ? "job" : "jobs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text("on".translated())
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    Text(agendaDateLabel(selectedDay))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
                Text(listJobsForSelectedDay.reduce(0) { $0 + $1.price }.currency)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.sweeplySurface)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.sweeplyBorder), alignment: .bottom)

            ScrollView {
                // Paycheck cards
                if hasPaychecks {
                    VStack(spacing: 8) {
                        ForEach(paychecks, id: \.id) { member in
                            paycheckCard(for: member)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                }

                if jobsStore.isLoading && jobsStore.jobs.isEmpty {
                    SkeletonList(count: 4).padding(.top, 16).padding(.horizontal, 20)
                } else if !hasJobs && !hasInvoices && !hasPaychecks {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                        Text("Nothing on \(agendaDateLabel(selectedDay))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text("Tap the date to choose another day.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            // Jobs section
            if hasJobs {
                Section {
                    VStack(spacing: 8) {
                        ForEach(listJobsForSelectedDay) { job in
                            ScheduleJobRow(job: job)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                } header: {
                    Text("")
                }
            }

                        // Invoices section
                        if hasInvoices {
                            Section {
                                VStack(spacing: 8) {
                                    ForEach(dayInvoices) { invoice in
                                        ScheduleInvoiceRow(invoice: invoice)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                            } header: {
                                HStack(spacing: 6) {
                                    Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                                    Text("INVOICES DUE".translated())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                        .tracking(0.8)
                                    Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.sweeplyBackground)
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

    // MARK: - Month View

    private var monthView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                JobberCalendarView(selectedDay: $selectedDay, jobs: ownJobs)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Text("Jobs for \(selectedDay.formatted(.dateTime.day().month()))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                let dayJobs = filteredJobsForDate(selectedDay)
                let dayInvoices = invoicesForDate(selectedDay)

                if dayJobs.isEmpty && dayInvoices.isEmpty {
                    scheduleEmptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(dayJobs) { job in
                            ScheduleJobRow(job: job)
                        }
                        if showInvoices && !dayInvoices.isEmpty {
                            if !dayJobs.isEmpty {
                                HStack(spacing: 6) {
                                    Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                                    Text("INVOICES DUE".translated())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                        .tracking(0.8)
                                    Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                                }
                            }
                            ForEach(dayInvoices) { invoice in
                                ScheduleInvoiceRow(invoice: invoice)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            await jobsStore.load(isAuthenticated: session.isAuthenticated)
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
        case .completed: return Color.sweeplyAccent
        case .inProgress: return Color.sweeplyWarning
        case .cancelled: return Color.sweeplyDestructive
        case .scheduled: return Color.sweeplyAccent.opacity(0.45)
        }
    }
}

private extension ScheduleView {

    // Only jobs belonging to this user's own business (excludes jobs assigned by other owners)
    private var ownJobs: [Job] {
        jobsStore.jobs.filter { $0.userId == session.userId }
    }

    private func filteredJobsForDate(_ date: Date) -> [Job] {
        ownJobs
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .filter { applyFilters($0) }
            .sorted { $0.date < $1.date }
    }

    private func invoicesForDate(_ date: Date) -> [Invoice] {
        guard showInvoices else { return [] }
        return invoicesStore.invoices
            .filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
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
            Text("No jobs this day".translated())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Tap + to schedule a job.".translated())
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Paycheck Cards

    private func paycheckMembers(for date: Date) -> [TeamMember] {
        let weekday = Calendar.current.component(.weekday, from: date)
        return teamStore.members.filter { member in
            guard member.payRateEnabled && member.payRateAmount > 0 else { return false }
            switch member.payRateType {
            case .perDay:
                return true
            case .perWeek:
                return member.payDayOfWeek == weekday
            default:
                return false
            }
        }
    }

    private func paycheckCard(for member: TeamMember) -> some View {
        let isWeekly = member.payRateType == .perWeek
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
                Text(isWeekly ? "WEEKLY PAYDAY" : "DAILY PAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.sweeplySuccess)
                    .tracking(0.8)
                Text(member.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
            }

            Spacer()

            Text(member.payRateAmount.currency)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.sweeplySuccess.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplySuccess.opacity(0.25), lineWidth: 1)
        )
    }

    private func computeColumns(_ jobs: [Job]) -> [(job: Job, column: Int, totalColumns: Int)] {
        let sorted = jobs.sorted { $0.date < $1.date }
        var result: [(job: Job, column: Int, totalColumns: Int)] = []
        var groupStart = 0

        while groupStart < sorted.count {
            var groupMaxEnd = sorted[groupStart].date.addingTimeInterval(sorted[groupStart].duration * 3600)
            var groupEnd = groupStart + 1
            while groupEnd < sorted.count {
                let job = sorted[groupEnd]
                if job.date < groupMaxEnd {
                    let end = job.date.addingTimeInterval(job.duration * 3600)
                    if end > groupMaxEnd { groupMaxEnd = end }
                    groupEnd += 1
                } else { break }
            }
            let group = Array(sorted[groupStart..<groupEnd])
            var columnEndTimes: [Date] = []
            var assignments: [(job: Job, column: Int)] = []
            for job in group {
                let col = columnEndTimes.firstIndex(where: { $0 <= job.date }) ?? columnEndTimes.count
                if col == columnEndTimes.count { columnEndTimes.append(Date.distantPast) }
                columnEndTimes[col] = job.date.addingTimeInterval(job.duration * 3600)
                assignments.append((job: job, column: col))
            }
            let total = columnEndTimes.count
            result.append(contentsOf: assignments.map { (job: $0.job, column: $0.column, totalColumns: total) })
            groupStart = groupEnd
        }
        return result
    }

}

// MARK: - Timeline Job Block

private struct TimelineJobBlock: View {
    let job: Job

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

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    var body: some View {
        NavigationLink(destination: JobDetailView(jobId: job.id)) {
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
                            Text("·".translated())
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
}

// MARK: - Row Components

private struct ScheduleMonthPicker: View {
    @Binding var selectedDay: Date
    let jobs: [Job]
    @Environment(\.dismiss) private var dismiss
    @State private var hasInteracted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            Button {
                dismiss()
            } label: {
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
            guard hasInteracted else {
                hasInteracted = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                dismiss()
            }
        }
        .onAppear { hasInteracted = false }
    }

    private var monthYearTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDay)
    }
}

private struct ScheduleJobRow: View {
    let job: Job
    @Environment(JobsStore.self) private var jobsStore
    @State private var showMenu = false
    @State private var showDeleteConfirm = false
    @State private var showInvoicePrompt = false
    @State private var showInvoiceSheet = false
    @State private var isPressed = false

    private var serviceAccentColor: Color {
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
        if d == d.rounded() { return "\(Int(d))h" }
        return String(format: "%.1fh", d)
    }

    var body: some View {
        NavigationLink(destination: JobDetailView(jobId: job.id)) {
            ZStack(alignment: .leading) {
                Color.sweeplySurface

                // Left accent bar — service-type color
                Capsule()
                    .fill(serviceAccentColor)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 0)

                HStack(spacing: 14) {
                    Color.clear.frame(width: 3)

                    VStack(alignment: .leading, spacing: 6) {
                        // Row 1: client name + recurring icon + duration pill + price
                        HStack(spacing: 4) {
                            Text(job.clientName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if job.isRecurring {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(serviceAccentColor)
                            }
                            Spacer()
                            // Duration pill
                            Text(durationLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(serviceAccentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(serviceAccentColor.opacity(0.1))
                                .clipShape(Capsule())
                            // Price
                            Text(job.price.currency)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }

                        // Row 2: time + elapsed timer if in progress
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                            Text(timeString(from: job.date))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                            if job.status == .inProgress {
                                Spacer()
                                ElapsedTimeView(startedAt: job.date)
                            }
                        }

                        // Row 3: service pill + status badge
                        HStack(spacing: 8) {
                            Text(job.serviceType.rawValue.translated())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(serviceAccentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(serviceAccentColor.opacity(0.1))
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
            Text("Are you sure you want to delete this job?".translated())
        }
        .alert("Create Invoice?", isPresented: $showInvoicePrompt) {
            Button("Not Now", role: .cancel) {}
            Button("Create Invoice".translated()) { showInvoiceSheet = true }
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
        case .inProgress: return inProgressColor
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

// MARK: - Schedule Invoice Row

private struct ScheduleInvoiceRow: View {
    let invoice: Invoice
    @State private var isPressed = false

    private var statusAccentColor: Color {
        switch invoice.status {
        case .paid:    return Color.sweeplyAccent
        case .unpaid:  return Color.sweeplyWarning
        case .overdue: return Color.sweeplyDestructive
        }
    }

    var body: some View {
        NavigationLink(destination: InvoiceDetailView(invoiceId: invoice.id)) {
            ZStack(alignment: .leading) {
                Color.sweeplySurface

                Capsule()
                    .fill(statusAccentColor)
                    .frame(width: 3)
                    .padding(.vertical, 10)

                HStack(spacing: 14) {
                    Color.clear.frame(width: 3)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(invoice.clientName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(invoice.total.currency)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 10))
                                .foregroundStyle(statusAccentColor.opacity(0.7))
                            Text("Due \(invoice.dueDate.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }

                        HStack(spacing: 8) {
                            Text(invoice.invoiceNumber)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.sweeplyBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            InvoiceStatusBadge(status: invoice.status)
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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(statusAccentColor.opacity(0.2), lineWidth: 1))
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
}

// MARK: - Week Strip

struct WeekStripView: View {
    @Binding var selectedDay: Date
    let jobs: [Job]

    @State private var weekOffset: Int = 0
    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }()

    private var todayWeekStart: Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    private func weekStart(for offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: todayWeekStart) ?? todayWeekStart
    }

    private func weeksFromToday(to date: Date) -> Int {
        let targetStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return calendar.dateComponents([.weekOfYear], from: todayWeekStart, to: targetStart).weekOfYear ?? 0
    }

    var body: some View {
        TabView(selection: $weekOffset) {
            ForEach(-52...52, id: \.self) { offset in
                weekRow(offset: offset)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 76)
        .onAppear {
            weekOffset = weeksFromToday(to: selectedDay)
        }
        .onChange(of: selectedDay) { _, newDay in
            let newOffset = weeksFromToday(to: newDay)
            if newOffset != weekOffset {
                withAnimation { weekOffset = newOffset }
            }
        }
        .onChange(of: weekOffset) { _, newOffset in
            let start = weekStart(for: newOffset)
            guard let end = calendar.date(byAdding: .day, value: 6, to: start) else { return }
            if selectedDay < start || selectedDay > end {
                let weekday = max(0, calendar.component(.weekday, from: selectedDay) - 1)
                let newDay = calendar.date(byAdding: .day, value: weekday, to: start) ?? start
                withAnimation(.easeInOut(duration: 0.2)) { selectedDay = newDay }
            }
        }
    }

    private func weekRow(offset: Int) -> some View {
        let start = weekStart(for: offset)
        return HStack(spacing: 6) {
            ForEach(0..<7) { dayIndex in
                let date = calendar.date(byAdding: .day, value: dayIndex, to: start) ?? start
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
                let isToday = calendar.isDateInToday(date)
                let hasJobs = jobs.contains { calendar.isDate($0.date, inSameDayAs: date) }
                let weekdayIdx = calendar.component(.weekday, from: date) - 1
                let shortLabel = calendar.shortWeekdaySymbols[weekdayIdx].prefix(3).uppercased()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDay = date }
                } label: {
                    VStack(spacing: 3) {
                        Text(shortLabel)
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 17, weight: .bold))
                        Circle()
                            .fill(hasJobs ? (isSelected ? Color.white.opacity(0.65) : Color.sweeplyAccent) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                    .background(
                        isSelected ? Color.sweeplyNavy :
                        (isToday ? Color.sweeplyAccent.opacity(0.08) : Color.sweeplySurface)
                    )
                    .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isToday && !isSelected ? Color.sweeplyAccent.opacity(0.45) : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Map Helper Views

struct MapPinView: View {
    let status: JobStatus
    let isSelected: Bool
    
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
        case .inProgress: return inProgressColor
        case .scheduled: return Color.sweeplyNavy.opacity(0.6)
        case .cancelled: return Color.sweeplyDestructive
        }
    }
    
    private let serviceIcon = "house.fill"
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

