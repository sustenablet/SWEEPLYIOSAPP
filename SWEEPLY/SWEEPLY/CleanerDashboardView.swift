import SwiftUI

struct CleanerDashboardView: View {
    @Environment(AppSession.self)   private var session
    @Environment(JobsStore.self)    private var jobsStore

    let membership: TeamMembership

    @State private var appeared = false
    @State private var selectedJobId: UUID? = nil
    @State private var showNotifications = false
    @State private var showProfileMenu = false
    @State private var showMemberSettings = false

    // MARK: - Derived

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var longDate: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var myJobs: [Job] {
        jobsStore.jobs.filter { $0.assignedMemberId == membership.id && $0.status != .cancelled }
    }

    private var todayJobs: [Job] {
        myJobs.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date }
    }

    private var weekCompleted: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return myJobs.filter { $0.date >= start && $0.status == .completed }.count
    }

    private var inProgressCount: Int {
        myJobs.filter { $0.status == .inProgress }.count
    }

    private var upcomingCount: Int {
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let end = tomorrow.addingTimeInterval(86400 * 7)
        return myJobs.filter { $0.date >= tomorrow && $0.date < end }.count
    }

    private var nextJobs: [(Date, [Job])] {
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let end = tomorrow.addingTimeInterval(86400 * 3)
        let upcoming = myJobs.filter { $0.date >= tomorrow && $0.date < end }.sorted { $0.date < $1.date }
        let groups = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }
        return groups.sorted { $0.key < $1.key }
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

                    // Hero stats strip
                    heroStrip
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 8)

                    // Card sections
                    VStack(spacing: 12) {
                        teamBanner
                        todaySection
                        if !nextJobs.isEmpty { upcomingSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.3)) { appeared = true }
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId)
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
            .sheet(isPresented: $showProfileMenu) {
                CleanerProfileMenuView(membership: membership, showSettings: $showMemberSettings)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
            }
            .fullScreenCover(isPresented: $showMemberSettings) {
                CleanerSettingsView(membership: membership)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        PageHeader(
            eyebrow: nil,
            title: longDate,
            subtitle: greeting
        ) {
            HStack(spacing: 12) {
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 40, height: 40)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button { showProfileMenu = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.sweeplyNavy)
                            .frame(width: 40, height: 40)
                        Image(systemName: "person.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hero Strip (4 stats)

    private var heroStrip: some View {
        HStack(spacing: 0) {
            statCell(value: "\(todayJobs.count)", label: "Today")
            stripDivider
            statCell(value: "\(weekCompleted)", label: "Done this wk")
            stripDivider
            statCell(value: "\(upcomingCount)", label: "Upcoming")
            stripDivider
            statCell(value: "\(inProgressCount)", label: "In Progress")
        }
        .padding(.vertical, 12)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1, height: 40)
    }

    // MARK: - Team Banner

    private var teamBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.sweeplyNavy)
                    .frame(width: 36, height: 36)
                Image(systemName: "building.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Working with")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(membership.businessName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }

            Spacer()

            Text(membership.role.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.sweeplyNavy.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    // MARK: - Today's Schedule

    private var todaySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Today's Schedule", action: nil)

                if jobsStore.isLoading {
                    skeletonRows
                } else if todayJobs.isEmpty {
                    emptyToday
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(todayJobs.enumerated()), id: \.element.id) { index, job in
                            CleanerDashJobRow(job: job)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedJobId = job.id
                                }
                            if index < todayJobs.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyToday: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyAccent.opacity(0.5))
            Text("You're all clear today")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var skeletonRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.sweeplyBorder.opacity(0.4))
                    .frame(height: 56)
            }
        }
    }

    // MARK: - Upcoming (next 3 days)

    private var upcomingSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Coming Up", subtitle: "Next 3 days", action: nil)

                VStack(spacing: 14) {
                    ForEach(nextJobs, id: \.0) { date, jobs in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(upcomingDayLabel(date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                    CleanerDashJobRow(job: job)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedJobId = job.id
                                        }
                                    if index < jobs.count - 1 {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func upcomingDayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}

// MARK: - CleanerDashJobRow

struct CleanerDashJobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 0) {
            // Left service-type accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(serviceColor(job.serviceType))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 10)

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
            .frame(width: 48)
            .padding(.vertical, 10)

            // Content
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
            .padding(.vertical, 10)

            Spacer(minLength: 8)

            // Right: price + status
            VStack(alignment: .trailing, spacing: 4) {
                Text(job.price.currency)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                statusPill(job.status)
            }
            .padding(.vertical, 10)
            .padding(.trailing, 2)
        }
    }

    private func durationLabel(_ hours: Double) -> String {
        let total = Int(hours * 60)
        let h = total / 60; let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func statusPill(_ status: JobStatus) -> some View {
        let color = statusColor(status)
        return Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .scheduled:  return Color.sweeplyAccent
        case .inProgress: return .orange
        case .completed:  return .green
        case .cancelled:  return Color.sweeplyTextSub
        }
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
