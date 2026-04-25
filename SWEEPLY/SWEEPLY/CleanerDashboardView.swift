import SwiftUI
import Charts

struct CleanerDashboardView: View {
    @Environment(AppSession.self)         private var session
    @Environment(JobsStore.self)          private var jobsStore
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(ProfileStore.self)       private var profileStore

    let membership: TeamMembership

    @State private var appeared = false
    @State private var selectedJobId: UUID? = nil
    @State private var showNotifications = false
    @State private var showProfileMenu = false
    @State private var showMemberSettings = false
    @State private var selectedHealthSlide = 0

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

    private var firstName: String {
        String(profileStore.profile?.fullName.split(separator: " ").first ?? "there")
    }

    private var initials: String {
        (profileStore.profile?.fullName ?? "")
            .split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
    }

    private var notificationsCount: Int {
        notificationsStore.notifications.filter { !$0.isRead }.count
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

    private var weekEarned: Double {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return myJobs.filter { $0.date >= start && $0.status == .completed }.reduce(0) { $0 + $1.price }
    }

    private var monthEarned: Double {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        return myJobs.filter { $0.date >= start && $0.status == .completed }.reduce(0) { $0 + $1.price }
    }

    private var monthJobCount: Int {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
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

    private var completionRate: Double {
        let total = myJobs.filter { $0.status != .scheduled }.count
        guard total > 0 else { return 0 }
        return Double(myJobs.filter { $0.status == .completed }.count) / Double(total) * 100
    }

    private var nextJob: Job? {
        myJobs.filter { ($0.status == .scheduled || $0.status == .inProgress) && $0.date >= Date() }
              .sorted { $0.date < $1.date }.first
    }

    private var weeklyEarningsData: [(week: Date, amount: Double)] {
        let cal = Calendar.current; let today = Date()
        return (0..<8).reversed().compactMap { ago -> (Date, Double)? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -ago, to: cal.startOfDay(for: today)),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
            let total = myJobs.filter { $0.status == .completed && $0.date >= start && $0.date < end }
                              .reduce(0.0) { $0 + $1.price }
            return (start, total)
        }
    }

    private var performanceCards: [DashboardHealthCardModel] {
        [
            DashboardHealthCardModel(
                title: "Earnings This Week",
                subtitle: "From completed jobs this week",
                value: weekEarned.currency,
                trend: weekCompleted > 0 ? "+\(weekCompleted) jobs" : "No completions",
                isPositive: weekCompleted > 0,
                icon: "dollarsign",
                iconColor: .sweeplyAccent,
                footnote: "\(weekCompleted) job\(weekCompleted == 1 ? "" : "s") completed this week",
                showTrendBadge: false
            ),
            DashboardHealthCardModel(
                title: "This Month",
                subtitle: "Earnings from completed jobs this month",
                value: monthEarned.currency,
                trend: "\(monthJobCount) completed",
                isPositive: monthJobCount > 0,
                icon: "calendar",
                iconColor: .sweeplyNavy,
                footnote: "\(monthJobCount) job\(monthJobCount == 1 ? "" : "s") done this month"
            ),
            DashboardHealthCardModel(
                title: "Completion Rate",
                subtitle: "Share of your jobs marked complete",
                value: completionRate > 0 ? String(format: "%.0f%%", completionRate) : "—",
                trend: completionRate >= 90 ? "On track" : completionRate > 0 ? "Keep it up" : "No data yet",
                isPositive: completionRate >= 80,
                icon: "checkmark.circle",
                iconColor: .sweeplyAccent,
                footnote: "\(myJobs.filter { $0.status == .completed }.count) of \(myJobs.filter { $0.status != .scheduled }.count) jobs completed"
            ),
            DashboardHealthCardModel(
                title: "Next Job",
                subtitle: nextJob.map { "For \($0.clientName)" } ?? "Nothing coming up",
                value: nextJob.map { timeUntil($0.date) } ?? "—",
                trend: nextJob?.serviceType.rawValue ?? "Clear schedule",
                isPositive: nextJob != nil,
                icon: "clock",
                iconColor: .sweeplyNavy,
                footnote: nextJob?.address.isEmpty == false ? nextJob!.address : "No upcoming jobs scheduled"
            )
        ]
    }

    private func timeUntil(_ date: Date) -> String {
        let diff = date.timeIntervalSince(Date())
        if diff <= 0 { return "Now" }
        let h = Int(diff / 3600)
        let m = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        if h >= 24 { return "\(h / 24)d away" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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

                    // Revenue hero + stats grid
                    HStack(alignment: .center, spacing: 20) {
                        revenueHero
                        cleanerStatsGrid
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.bottom, 24)

                    // Card sections
                    VStack(spacing: 12) {
                        teamBanner
                        todaySection
                        performanceSection
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
                CleanerJobDetailView(jobId: jobId, ownerId: membership.ownerId)
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
            subtitle: "\(greeting), \(firstName)"
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
                        .overlay(alignment: .topTrailing) {
                            if notificationsCount > 0 {
                                Circle()
                                    .fill(Color.sweeplyDestructive)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .buttonStyle(.plain)

                Button { showProfileMenu = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.sweeplyNavy)
                            .frame(width: 40, height: 40)
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Revenue Hero

    private var revenueHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EARNINGS THIS WEEK")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            Text(weekEarned.currency)
                .font(.system(size: 42, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .tracking(-1.5)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if weekCompleted > 0 {
                Text("\(weekCompleted) job\(weekCompleted == 1 ? "" : "s") completed")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            } else {
                Text("No completed jobs yet this week")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            if !weeklyEarningsData.isEmpty {
                Chart(weeklyEarningsData, id: \.week) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        y: .value("Earned", point.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sweeplyAccent.opacity(0.3), Color.sweeplyAccent.opacity(0.0)],
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
                .frame(height: 36)
                .animation(.easeOut(duration: 0.6), value: weeklyEarningsData.map(\.amount))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Stats Grid (2x2)

    private var cleanerStatsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            CleanerStatBox(value: "\(todayJobs.count)", label: "Today")
            CleanerStatBox(value: "\(weekCompleted)", label: "Done Wk")
            CleanerStatBox(value: "\(upcomingCount)", label: "Upcoming")
            CleanerStatBox(value: "\(inProgressCount)", label: "In Prog.")
        }
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

    // MARK: - Performance Section

    private var performanceSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Performance", subtitle: "Swipe through your stats", action: nil)

                TabView(selection: $selectedHealthSlide) {
                    ForEach(Array(performanceCards.enumerated()), id: \.offset) { index, card in
                        DashboardHealthSlide(card: card)
                            .tag(index)
                            .padding(.vertical, 2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 178)

                HStack(spacing: 8) {
                    ForEach(performanceCards.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedHealthSlide ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.8))
                            .frame(width: index == selectedHealthSlide ? 18 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: selectedHealthSlide)
                    }
                    Spacer()
                    Text("\(selectedHealthSlide + 1) / \(performanceCards.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
}

// MARK: - CleanerStatBox

private struct CleanerStatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
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
