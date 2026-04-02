import SwiftUI

// MARK: - Schedule (Jobber-style day / list / map)

enum ScheduleViewMode: String, CaseIterable {
    case day = "Day"
    case list = "List"
    case map = "Map"
}

struct ScheduleView: View {
    @State private var jobs: [Job] = MockData.makeJobs()
    @State private var weekOffset: Int = 0
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var viewMode: ScheduleViewMode = .day
    @State private var appeared = false
    @State private var showMonthPicker = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }

    private var weekInterval: DateInterval {
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return calendar.dateInterval(of: .weekOfYear, for: anchor)
            ?? DateInterval(start: Date(), end: Date())
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: weekInterval.start)
        }
    }

    private var jobsForSelectedDay: [Job] {
        jobs
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date < $1.date }
    }

    private var resourceFirstName: String {
        MockData.profile.fullName.split(separator: " ").first.map(String.init) ?? "You"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topToolbar
                modeSegment
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                weekStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                resourceRow
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Group {
                    switch viewMode {
                    case .day:
                        dayTimelineScroll
                    case .list:
                        listModeScroll
                    case .map:
                        mapPlaceholder
                    }
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .onChange(of: weekOffset) { _, _ in
            if !weekDays.contains(where: { calendar.isDate($0, inSameDayAs: selectedDay) }) {
                selectedDay = calendar.startOfDay(for: weekInterval.start)
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker(
                        "Go to",
                        selection: Binding(
                            get: { selectedDay },
                            set: { newVal in
                                selectedDay = calendar.startOfDay(for: newVal)
                                syncWeekOffsetToSelectedDay()
                            }
                        ),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    Spacer()
                }
                .navigationTitle("Choose date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showMonthPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func syncWeekOffsetToSelectedDay() {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
        let ref = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let diff = calendar.dateComponents([.weekOfYear], from: ref, to: start).weekOfYear ?? 0
        weekOffset = diff
    }

    // MARK: Top toolbar (month + icons)

    private var topToolbar: some View {
        HStack(alignment: .center) {
            Button {
                showMonthPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(monthTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                iconToolbarButton("calendar") { showMonthPicker = true }
                iconToolbarButton("line.3.horizontal.decrease.circle") { }
                iconToolbarButton("wand.and.stars") { }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: selectedDay)
    }

    private func iconToolbarButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(Color.sweeplyNavy)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: Day / List / Map segment

    private var modeSegment: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
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

    // MARK: Resource row

    private var resourceRow: some View {
        HStack {
            Text(resourceFirstName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
            Text("\(jobsForSelectedDay.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(minWidth: 28, minHeight: 28)
                .background(Color(red: 0.93, green: 0.93, blue: 0.94))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Day timeline

    /// First hour label (6 AM). Last label is 9 PM (`timelineEndExclusive` - 1).
    private static let timelineStartHour = 6
    private static let timelineEndExclusive = 22
    private static let hourRowHeight: CGFloat = 52

    private var dayTimelineScroll: some View {
        ScrollView {
            dayTimelineContent
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
        }
    }

    private var dayTimelineContent: some View {
        let startH = Self.timelineStartHour
        let endEx = Self.timelineEndExclusive
        let hourH = Self.hourRowHeight
        let hourRange = Array(startH..<endEx)
        let slotCount = hourRange.count
        let totalHeight = CGFloat(slotCount) * hourH

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(hourRange, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(width: 48, height: hourH, alignment: .top)
                }
            }

            ZStack(alignment: .topLeading) {
                ForEach(0..<slotCount, id: \.self) { i in
                    Rectangle()
                        .fill(Color.sweeplyBorder.opacity(0.75))
                        .frame(height: 1)
                        .offset(y: CGFloat(i) * hourH)
                }

                if calendar.isDateInToday(selectedDay) {
                    currentTimeIndicator(
                        totalHeight: totalHeight,
                        startHour: startH,
                        hourHeight: hourH
                    )
                }

                ForEach(jobsForSelectedDay) { job in
                    NavigationLink {
                        ScheduleJobDetailView(job: job)
                    } label: {
                        ScheduleTimelineBlock(job: job, hourHeight: hourH)
                    }
                    .buttonStyle(.plain)
                    .offset(y: jobYOffset(job, startHour: startH, hourHeight: hourH))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: totalHeight, alignment: .top)
            .clipped()
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12: Int
        if hour == 0 { h12 = 12 }
        else if hour > 12 { h12 = hour - 12 }
        else { h12 = hour }
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(h12) \(suffix)"
    }

    private func jobYOffset(_ job: Job, startHour: Int, hourHeight: CGFloat) -> CGFloat {
        let start = calendar.startOfDay(for: selectedDay)
        let comps = calendar.dateComponents([.hour, .minute], from: start, to: job.date)
        let h = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        let fromStart = h - Double(startHour)
        return CGFloat(max(0, fromStart)) * hourHeight
    }

    @ViewBuilder
    private func currentTimeIndicator(totalHeight: CGFloat, startHour: Int, hourHeight: CGFloat) -> some View {
        let now = Date()
        if calendar.isDate(now, inSameDayAs: selectedDay) {
            let start = calendar.startOfDay(for: selectedDay)
            let comps = calendar.dateComponents([.hour, .minute], from: start, to: now)
            let h = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
            let y = CGFloat(h - Double(startHour)) * hourHeight
            if y >= 0 && y <= totalHeight {
                HStack(alignment: .center, spacing: 0) {
                    Circle()
                        .stroke(Color.blue.opacity(0.9), lineWidth: 2)
                        .frame(width: 8, height: 8)
                        .background(Circle().fill(Color.sweeplySurface))
                    Rectangle()
                        .fill(Color.blue.opacity(0.85))
                        .frame(height: 2)
                }
                .offset(y: y)
            }
        }
    }

    // MARK: List mode

    private var listModeScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if jobsForSelectedDay.isEmpty {
                    scheduleEmptyState
                } else {
                    ForEach(jobsForSelectedDay) { job in
                        NavigationLink {
                            ScheduleJobDetailView(job: job)
                        } label: {
                            ScheduleJobRow(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    // MARK: Map placeholder

    private var mapPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.92, green: 0.92, blue: 0.93))
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.45))
                Text("Map view")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text("Route planning will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.8))
            }
            .padding(24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 100)
    }

    private var scheduleEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.45))
            Text("Nothing scheduled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Jobs you add will show up here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

// MARK: - Timeline block

private struct ScheduleTimelineBlock: View {
    let job: Job
    let hourHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.sweeplySuccess.opacity(0.9))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
                Text(timeRange)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .frame(height: blockHeight)
        .padding(.leading, 4)
    }

    private var blockHeight: CGFloat {
        max(56, CGFloat(job.duration) * hourHeight)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let start = f.string(from: job.date)
        let end = f.string(from: job.date.addingTimeInterval(job.duration * 3600))
        return "\(start) – \(end)"
    }
}

// MARK: - Row (list mode)

private struct ScheduleJobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                    .monospacedDigit()
                Text("\(durationText) · \(job.price.currency)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(width: 100, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.clientName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
                if !job.address.isEmpty {
                    Text(job.address)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.9))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(status: job.status)
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let start = f.string(from: job.date)
        let endDate = job.date.addingTimeInterval(job.duration * 3600)
        return "\(start) – \(f.string(from: endDate))"
    }

    private var durationText: String {
        if job.duration == floor(job.duration) {
            return "\(Int(job.duration)) hr"
        }
        return String(format: "%.1f hr", job.duration)
    }
}

// MARK: - Detail

struct ScheduleJobDetailView: View {
    let job: Job

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.clientName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    StatusBadge(status: job.status)
                }

                detailRow(icon: "wrench.and.screwdriver", title: "Service", value: job.serviceType.rawValue)
                detailRow(icon: "clock", title: "Time", value: timeBlock)
                detailRow(icon: "dollarsign.circle", title: "Price", value: job.price.currency)
                detailRow(icon: "mappin.and.ellipse", title: "Location", value: job.address.isEmpty ? "—" : job.address)
                detailRow(icon: "arrow.triangle.2.circlepath", title: "Recurring", value: job.isRecurring ? "Yes" : "No")
            }
            .padding(20)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var timeBlock: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · h:mm a"
        return f.string(from: job.date)
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    .tracking(0.8)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

#Preview {
    ScheduleView()
}
