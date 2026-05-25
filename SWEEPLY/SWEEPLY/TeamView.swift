import SwiftUI

// MARK: - TeamView

struct TeamView: View {
    @Environment(TeamStore.self)    private var teamStore
    @Environment(JobsStore.self)    private var jobsStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session
    @Environment(\.dismiss)         private var dismiss

    @State private var showInvite        = false
    @State private var selectedMember:   TeamMember? = nil
    @State private var deleteTarget:     TeamMember? = nil
    @State private var showDeleteConfirm = false
    @State private var acceptingInviteId: UUID? = nil
    @State private var decliningInviteId: UUID? = nil
    @State private var selectedTeamSlide = 0
    @State private var selectedPerformanceRange: TeamPerformanceRange = .month

    private let teamCarouselHeight: CGFloat = 160

    private enum TeamPerformanceRange: String, CaseIterable {
        case week, month, all

        var label: String {
            switch self {
            case .week: return "Week".translated()
            case .month: return "Month".translated()
            case .all: return "All".translated()
            }
        }
    }

    // MARK: - Derived

    private var cleaners: [TeamMember]   { teamStore.members.filter { $0.role == .member } }
    private var totalCrewCount: Int      { teamStore.members.count + 1 }
    private var activeCount: Int         { teamStore.members.filter { $0.status == .active  }.count }
    private var invitedCount: Int        { teamStore.members.filter { $0.status == .invited }.count }
    private var inactiveCount: Int       { teamStore.members.filter { $0.status == .inactive }.count }
    private var teamJobs: [Job] {
        guard !cleaners.isEmpty else { return [] }
        return jobsStore.jobs.filter { job in
            job.status != .cancelled && cleaners.contains(where: { job.isAssigned(to: $0.id) })
        }
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    private var weekTeamJobs: [Job] { teamJobs.filter { $0.date >= weekStart } }
    private var monthTeamJobs: [Job] { teamJobs.filter { $0.date >= monthStart } }
    private var allTeamJobs: [Job] { teamJobs }

    private var weekAssignedCount: Int { weekTeamJobs.count }
    private var weekCompletedCount: Int { weekTeamJobs.filter { $0.status == .completed }.count }
    private var weekUpcomingCount: Int {
        weekTeamJobs.filter { ($0.status == .scheduled || $0.status == .inProgress) && $0.date >= Date() }.count
    }

    private var performanceSubtitle: String {
        "Week".translated() + " / " + "Month".translated() + " / " + "All".translated()
    }

    private var performanceJobs: [Job] {
        switch selectedPerformanceRange {
        case .week:
            return weekTeamJobs
        case .month:
            return monthTeamJobs
        case .all:
            return allTeamJobs
        }
    }

    private var performanceAssignedCount: Int { performanceJobs.count }
    private var performanceCompletedCount: Int { performanceJobs.filter { $0.status == .completed }.count }
    private var performanceUpcomingCount: Int {
        performanceJobs.filter { ($0.status == .scheduled || $0.status == .inProgress) && $0.date >= Date() }.count
    }
    private var performanceEarned: Double {
        performanceJobs.filter { $0.status == .completed }.reduce(0) { $0 + $1.price }
    }

    private var weekCompletionPct: Int {
        weekAssignedCount > 0 ? Int(Double(weekCompletedCount) / Double(weekAssignedCount) * 100) : 0
    }
    private var weekCompletionHeroColor: Color {
        weekCompletionPct >= 80 ? Color.sweeplySuccess
            : weekCompletionPct >= 40 ? Color.sweeplyWarning
            : Color.sweeplyNavy
    }

    private var payrollMembers: [TeamMember] {
        cleaners.sorted { lhs, rhs in
            if lhs.payRateEnabled != rhs.payRateEnabled {
                return lhs.payRateEnabled && !rhs.payRateEnabled
            }
            if lhs.status != rhs.status {
                return lhs.status == .active
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var payrollConfiguredCount: Int {
        payrollMembers.filter { $0.payRateEnabled }.count
    }

    private var payrollNeedsSetupCount: Int {
        payrollMembers.filter { !$0.payRateEnabled }.count
    }

    private var payrollCoverageRatio: Double {
        guard !cleaners.isEmpty else { return 0 }
        return Double(payrollConfiguredCount) / Double(cleaners.count)
    }

    private var payrollEstimatedTotal: Double {
        payrollMembers.reduce(0) { total, member in
            total + estimatedPayrollAmount(for: member)
        }
    }

    private var nearestPayrollDate: Date? {
        payrollMembers.compactMap { nextPaydayDate(for: $0) }.min()
    }

    private var nearestPayrollLabel: String {
        guard let nearestPayrollDate else { return "—" }
        return nearestPayrollDate.formatted(.dateTime.locale(Locale.app).weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // Hero header — owner identity + team stats
                        teamHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 20)

                        // Pending invites (conditional)
                        if !session.pendingInvites.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(session.pendingInvites) { invite in
                                    pendingInviteCard(invite)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }

                        // Error
                        if let err = teamStore.lastError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyDestructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }

                        // Roster — individual cards
                        rosterSection

                        // Payroll hub
                        payrollSection

                        Spacer(minLength: 48)
                    }
                }
                .refreshable {
                    if let uid = session.userId {
                        await teamStore.load(ownerId: uid)
                    }
                }
            }
            .navigationTitle("My Team".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done".translated()) { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showInvite = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Invite".translated())
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.sweeplyNavy)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showInvite) {
                InviteMemberSheet(ownerId: session.userId ?? UUID())
                    .environment(teamStore)
                    .environment(profileStore)
            }
            .fullScreenCover(item: $selectedMember) { member in
                MemberDetailView(member: member)
                    .environment(teamStore)
                    .environment(profileStore)
                    .environment(session)
            }
            .confirmationDialog(
                "Remove \(deleteTarget?.name ?? "member") from your team?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove".translated(), role: .destructive) {
                    guard let target = deleteTarget else { return }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    Task { await teamStore.remove(id: target.id) }
                    deleteTarget = nil
                }
                Button("Cancel".translated(), role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This will remove them from your roster. You can invite them again anytime.".translated())
            }
        }
    }

    // MARK: - Team Header

    private var teamHeader: some View {
        TabView(selection: $selectedTeamSlide) {
            overviewSlide
                .tag(0)
            statusSlide
                .tag(1)
            operationsSlide
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: teamCarouselHeight)
        .animation(.easeInOut(duration: 0.2), value: selectedTeamSlide)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            teamCarouselIndicator
                .padding(.trailing, 14)
                .padding(.top, 12)
        }
    }

    // MARK: - Carousel Slides (redesigned)

    // MARK: - Carousel Slides (Premium)

    // MARK: - Carousel Slides

    // Slide 1 — crew breakdown: hero number left, separated stat list right
    private var overviewSlide: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 5) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Overview".translated().uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.7)
                Spacer()
            }
            .padding(.bottom, 9)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalCrewCount)")
                        .font(.system(size: 41, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    Text("Members".translated().uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.6)
                }
                .frame(minWidth: 58, alignment: .leading)

                // Status list with hairline separators
                VStack(spacing: 0) {
                    crewStatRow(value: "\(activeCount)",   label: "Active".translated(),   tint: Color.sweeplySuccess)
                        .padding(.vertical, 4)
                    Rectangle().fill(Color.sweeplyBorder.opacity(0.45)).frame(height: 0.5)
                    crewStatRow(value: "\(invitedCount)",  label: "Pending".translated(),  tint: Color.sweeplyWarning)
                        .padding(.vertical, 4)
                    Rectangle().fill(Color.sweeplyBorder.opacity(0.45)).frame(height: 0.5)
                    crewStatRow(value: "\(inactiveCount)", label: "Inactive".translated(), tint: Color.sweeplyTextSub.opacity(0.45))
                        .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Setup coverage".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.6)
                    Spacer()
                    Text(payrollMembers.isEmpty ? "0/0" : "\(payrollConfiguredCount)/\(cleaners.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.sweeplyBorder.opacity(0.45))
                        Capsule()
                            .fill(Color.sweeplyAccent)
                            .frame(width: geo.size.width * payrollCoverageRatio)
                    }
                }
                .frame(height: 6)

                HStack(spacing: 10) {
                    overviewMiniMetric(
                        value: payrollMembers.isEmpty ? "0" : "\(payrollConfiguredCount)",
                        label: "Configured".translated(),
                        tint: Color.sweeplySuccess
                    )
                    overviewMiniMetric(
                        value: payrollMembers.isEmpty ? "0" : "\(payrollNeedsSetupCount)",
                        label: "Needs setup".translated(),
                        tint: Color.sweeplyWarning
                    )
                    overviewMiniMetric(
                        value: nearestPayrollLabel,
                        label: "Next payday".translated(),
                        tint: Color.sweeplyAccent
                    )
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Slide 2 — this week: 3-column stat grid (intentionally different from slides 1 & 3)
    private var statusSlide: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.sweeplySuccess)
                Text("This Week".translated().uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.7)
                Spacer()
            }
            .padding(.bottom, 14)

            // 3-column centered stat grid
            HStack(spacing: 0) {
                weekStatColumn(
                    value: "\(weekAssignedCount)",
                    label: "Assigned".translated(),
                    tint: Color.sweeplyNavy
                )

                Rectangle()
                    .fill(Color.sweeplyBorder.opacity(0.5))
                    .frame(width: 0.5, height: 44)

                weekStatColumn(
                    value: "\(weekCompletedCount)",
                    label: "Completed".translated(),
                    tint: Color.sweeplySuccess
                )

                Rectangle()
                    .fill(Color.sweeplyBorder.opacity(0.5))
                    .frame(width: 0.5, height: 44)

                weekStatColumn(
                    value: "\(weekUpcomingCount)",
                    label: "Upcoming".translated(),
                    tint: Color.sweeplyWarning
                )
            }
            .frame(maxWidth: .infinity)

            // Completion context line
            HStack(spacing: 4) {
                Text("\(weekCompletionPct)%".translated())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(weekCompletionHeroColor)
                Text("of jobs completed this week".translated())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                Spacer()
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Slide 3 — performance: hero earned + separated stat list right, range picker in header
    private var operationsSlide: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header + inline range picker
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.sweeplyWarning)
                    Text("Performance".translated().uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.7)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(TeamPerformanceRange.allCases, id: \.self) { range in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedPerformanceRange = range
                        } label: {
                            Text(range.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(selectedPerformanceRange == range ? .white : Color.sweeplyTextSub)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(selectedPerformanceRange == range
                                        ? Color.sweeplyNavy
                                        : Color.sweeplyBorder.opacity(0.4))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 12)

            HStack(alignment: .center, spacing: 18) {
                // Hero: total earned
                VStack(alignment: .leading, spacing: 2) {
                    Text(performanceEarned.currencyWithoutTrailingZeros)
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                    Text("Earned".translated().uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.6)
                }
                .frame(minWidth: 70, alignment: .leading)

                // Stat list with hairline separators
                VStack(spacing: 0) {
                    crewStatRow(value: "\(performanceAssignedCount)",  label: "Assigned".translated(),  tint: Color.sweeplyNavy)
                        .padding(.vertical, 6)
                    Rectangle().fill(Color.sweeplyBorder.opacity(0.45)).frame(height: 0.5)
                    crewStatRow(value: "\(performanceCompletedCount)", label: "Completed".translated(), tint: Color.sweeplySuccess)
                        .padding(.vertical, 6)
                    Rectangle().fill(Color.sweeplyBorder.opacity(0.45)).frame(height: 0.5)
                    crewStatRow(value: "\(performanceUpcomingCount)",  label: "Upcoming".translated(),  tint: Color.sweeplyWarning)
                        .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Slide sub-components

    // Stat row used in slides 1 & 3: dot + label + right-aligned number
    private func crewStatRow(value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.primary)
        }
    }

    private func overviewMiniMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Centered column used only in slide 2
    private func weekStatColumn(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .black, design: .monospaced))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var teamCarouselIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == selectedTeamSlide ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.6))
                    .frame(width: index == selectedTeamSlide ? 16 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: selectedTeamSlide)
            }
        }
    }



    // MARK: - Roster Section

    private var rosterSection: some View {
        VStack(spacing: 0) {
            if cleaners.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
            } else {
                // Section label
                HStack(spacing: 6) {
                    Text("YOUR CREW".translated())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("\(cleaners.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Individual member cards
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(cleaners) { member in
                            memberCard(member)
                        }
                        addMemberCard
                    }
                    .padding(.horizontal, 20)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: - Payroll Section

    private var payrollSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Team Payroll".translated())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Estimated this month".translated())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(payrollEstimatedTotal.currencyWithoutTrailingZeros)
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(payrollMembers.isEmpty
                             ? "No team members yet".translated()
                             : "\(payrollMembers.count) " + "Cleaners".translated())
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        payrollMetricColumn(
                            value: payrollMembers.isEmpty ? "0" : "\(payrollConfiguredCount)/\(cleaners.count)",
                            label: "Setup coverage".translated(),
                            tint: Color.sweeplySuccess
                        )

                        Rectangle()
                            .fill(Color.sweeplyBorder.opacity(0.5))
                            .frame(width: 0.5, height: 38)

                        payrollMetricColumn(
                            value: payrollMembers.isEmpty ? "0" : "\(payrollNeedsSetupCount)",
                            label: "Needs setup".translated(),
                            tint: Color.sweeplyWarning
                        )

                        Rectangle()
                            .fill(Color.sweeplyBorder.opacity(0.5))
                            .frame(width: 0.5, height: 38)

                        payrollMetricColumn(
                            value: nearestPayrollLabel,
                            label: "Next payday".translated(),
                            tint: Color.sweeplyAccent
                        )
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                if payrollMembers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
                        Text("Add your crew to start tracking payroll.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(payrollMembers.prefix(4).enumerated()), id: \.element.id) { index, member in
                            payrollRow(member)

                            if index < min(payrollMembers.count, 4) - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func payrollMetricColumn(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.sweeplyTextSub)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func payrollRow(_ member: TeamMember) -> some View {
        let est = estimatedPayrollAmount(for: member)
        let nextPay = nextPaydayLabel(for: member)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedMember = member
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(member.avatarTone.backgroundColor)
                        .frame(width: 36, height: 36)
                    Text(member.initials.isEmpty ? "?" : member.initials)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(member.avatarTone.foregroundColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        if member.payRateEnabled {
                            statusBadge(label: "Configured".translated(), tint: Color.sweeplySuccess)
                        } else {
                            statusBadge(label: "Needs setup".translated(), tint: Color.sweeplyWarning)
                        }
                    }

                    Text(member.payRateEnabled ? member.payRateDescription : "Tap to set up payroll.".translated())
                        .font(.system(size: 11))
                        .foregroundStyle(member.payRateEnabled ? Color.sweeplyAccent : Color.sweeplyTextSub)
                        .lineLimit(2)

                    if let nextPay {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .semibold))
                            Text(nextPay)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color.sweeplyTextSub)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(est.currencyWithoutTrailingZeros)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("This month".translated())
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func nextPaydayDate(for member: TeamMember) -> Date? {
        guard let payDay = member.payDayOfWeek else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeekday = calendar.component(.weekday, from: today)

        var daysUntilPayday = payDay - currentWeekday
        if daysUntilPayday <= 0 { daysUntilPayday += 7 }

        return calendar.date(byAdding: .day, value: daysUntilPayday, to: today)
    }

    private func nextPaydayLabel(for member: TeamMember) -> String? {
        guard let nextPaydayDate = nextPaydayDate(for: member) else { return nil }
        return nextPaydayDate.formatted(.dateTime.locale(Locale.app).weekday(.abbreviated).month(.abbreviated).day())
    }

    private func estimatedPayrollAmount(for member: TeamMember) -> Double {
        guard member.payRateEnabled else { return 0 }

        let jobs = completedJobsThisMonth(for: member)
        let cal = Calendar.current

        switch member.payRateType {
        case .perJob:
            return jobs.reduce(0.0) { acc, job in
                let rate = member.serviceRates[job.serviceType.rawValue] ?? member.payRateAmount
                return acc + rate
            }
        case .perDay:
            let dailyTotals = Dictionary(grouping: jobs) { job in
                cal.startOfDay(for: job.date)
            }
            return dailyTotals.values.reduce(0.0) { acc, _ in acc + member.payRateAmount }
        case .perWeek:
            return member.payRateAmount
        case .custom:
            return member.payRateAmount
        }
    }

    private func completedJobsThisMonth(for member: TeamMember) -> [Job] {
        guard let start = Calendar.current.dateInterval(of: .month, for: Date())?.start else { return [] }
        return jobsStore.jobs.filter { job in
            job.isAssigned(to: member.id) && job.status == .completed && job.date >= start
        }
    }

    // MARK: - Member Card

    private func memberCard(_ member: TeamMember) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedMember = member
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(
                                member.status == .invited
                                    ? AnyShapeStyle(member.avatarTone.backgroundColor.opacity(0.15))
                                    : AnyShapeStyle(member.avatarTone.backgroundColor)
                            )
                            .frame(width: 56, height: 56)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        member.status == .invited
                                            ? member.avatarTone.backgroundColor.opacity(0.4)
                                            : Color.clear,
                                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                    )
                            )
                        Text(member.initials.isEmpty ? "?" : member.initials)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(
                                member.status == .invited
                                    ? member.avatarTone.backgroundColor
                                    : member.avatarTone.foregroundColor
                            )
                    }
                    .padding(.top, 4)

                    Circle()
                        .fill(statusColor(member.status))
                        .frame(width: 11, height: 11)
                        .overlay(
                            Circle()
                                .stroke(Color.sweeplySurface, lineWidth: 2)
                        )
                        .offset(x: 4, y: -2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            member.status == .invited
                                ? Color.sweeplyNavy.opacity(0.45)
                                : Color.sweeplyNavy
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if member.status == .invited {
                        Text("Invite sent".translated())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyWarning)
                            .lineLimit(2)
                    } else {
                        Text(member.payRateDescription)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 156, height: 148, alignment: .topLeading)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteTarget = member
                showDeleteConfirm = true
            } label: {
                Label("Remove".translated(), systemImage: "trash")
            }
        }
    }

    private var addMemberCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showInvite = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyTextSub.opacity(0.10))
                        .frame(width: 56, height: 56)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite Another Cleaner".translated())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text("Add a new member to your team".translated())
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 156, height: 148, alignment: .topLeading)
            .background(Color.sweeplySurface.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.sweeplyBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusColor(_ status: TeamMemberStatus) -> Color {
        switch status {
        case .active:   return Color.sweeplySuccess
        case .invited:  return Color.sweeplyWarning
        case .inactive: return Color.sweeplyTextSub
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.sweeplyAccent.opacity(0.45))
            }

            VStack(spacing: 8) {
                Text("Your crew starts here".translated())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Add your first cleaner to start assigning\njobs and tracking their work.".translated())
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showInvite = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Invite Your First Cleaner".translated())
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.sweeplyNavy, in: Capsule())
                .shadow(color: Color.sweeplyNavy.opacity(0.18), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Pending Invite Card

    private func pendingInviteCard(_ invite: PendingInvite) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyWarning.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sweeplyWarning)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(invite.businessName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                Text("Invited you as %@".translated(with: invite.role.capitalized))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    decliningInviteId = invite.id
                    Task {
                        await session.declineInvite(memberId: invite.id)
                        decliningInviteId = nil
                    }
                } label: {
                    Text(decliningInviteId == invite.id ? "…" : "Decline".translated())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.sweeplyBorder.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(acceptingInviteId != nil || decliningInviteId != nil)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    acceptingInviteId = invite.id
                    Task {
                        await session.acceptInvite(memberId: invite.id)
                        acceptingInviteId = nil
                    }
                } label: {
                    Group {
                        if acceptingInviteId == invite.id {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Text("Accept".translated())
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.sweeplyNavy, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(acceptingInviteId != nil || decliningInviteId != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyWarning.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.sweeplyWarning)
                .frame(width: 4)
                .padding(.vertical, 10)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - MemberDetailView

struct MemberDetailView: View {
    @Environment(TeamStore.self)     private var teamStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(ProfileStore.self)  private var profileStore
    @Environment(AppSession.self)    private var session
    @Environment(\.dismiss)          private var dismiss

    let member: TeamMember

    // Contact edit
    @State private var isEditing = false
    @State private var localName: String
    @State private var localEmail: String
    @State private var localPhone: String
    @State private var isSavingContact = false

    // Pay setup wizard
    @State private var showPaySetup = false

    // History tab (combines Job History + Payment History)
    enum HistoryTab { case jobs, payments }
    @State private var historyTab: HistoryTab = .jobs

    // Status / removal
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false
    @State private var inviteMessage = ""

    // Payment history
    @State private var payments: [TeamMemberPayment] = []
    @State private var isLoadingPayments = false
    @State private var showRecordPayment = false

    // Full history sheet
    @State private var showFullHistory = false
    @State private var fullHistoryInitialTab: HistoryTab = .jobs

    // Job detail from history tap
    @State private var selectedJobForDetail: UUID? = nil
    @State private var showJobFromHistory = false

    init(member: TeamMember) {
        self.member = member
        _localName = State(initialValue: member.name)
        _localEmail = State(initialValue: member.email)
        _localPhone = State(initialValue: member.phone)
    }

    // MARK: - Derived

    private var hasContactChanges: Bool {
        localName.trimmingCharacters(in: .whitespaces) != member.name ||
        localEmail.trimmingCharacters(in: .whitespaces) != member.email ||
        localPhone.trimmingCharacters(in: .whitespaces) != member.phone
    }

    // Always read live data from the store so the card refreshes after pay setup closes
    private var currentMember: TeamMember {
        teamStore.members.first(where: { $0.id == member.id }) ?? member
    }

    private var paySetupSummary: String {
        let m = currentMember
        guard m.payRateEnabled else { return "Not configured".translated() }
        let key = "memberPayMethod_\(m.id.uuidString)"
        let methodRaw = UserDefaults.standard.string(forKey: key) ?? ""
        let via = PaymentMethod(rawValue: methodRaw)?.rawValue ?? ""
        let viaSuffix = via.isEmpty ? "" : " · \(via)"
        switch m.payRateType {
        case .perJob:
            let count = m.serviceRates.filter { $0.value > 0 }.count
            return count > 0 ? "%d service rates · %@%@".translated(with: count, "Per Job".translated(), viaSuffix) : "%@%@".translated(with: "Per Job".translated(), viaSuffix)
        case .perDay:   return "%@ %@%@".translated(with: m.payRateAmount.currency, "per day".translated(), viaSuffix)
        case .perWeek:  return "%@ %@%@".translated(with: m.payRateAmount.currency, "per week".translated(), viaSuffix)
        case .custom:   return "%@%@".translated(with: "Custom".translated(), viaSuffix)
        }
    }

    private func cityFromAddress(_ address: String) -> String {
        let parts = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count >= 2 ? parts[1] : (parts.first ?? address)
    }

    private func weekdayName(_ weekday: Int) -> String {
        // Calendar weekday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let idx = max(0, min(6, weekday - 1))
        return names[idx]
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    memberProfileCard
                    performanceCard
                    paySetupCard
                    historyCard
                    statusActionsCard
                    removeButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 56)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .principal) {
                    Text(member.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isEditing && hasContactChanges {
                            Task { await saveContact() }
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                        }
                    }
                    .font(.system(size: 15, weight: isEditing ? .semibold : .medium))
                    .foregroundStyle(isEditing ? Color.sweeplyNavy : Color.sweeplyTextSub)
                }
            }
            .confirmationDialog(
                "Remove \(member.name) from your team?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove".translated(), role: .destructive) {
                    Task {
                        let ok = await teamStore.remove(id: member.id)
                        if ok { dismiss() }
                    }
                }
            } message: {
                Text("You can invite them again anytime.".translated())
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [inviteMessage])
            }
            .sheet(isPresented: $showRecordPayment) {
                RecordPaymentSheet(member: member) { amount, notes in
                    guard let ownerId = session.userId else { return }
                    let biz = profileStore.profile?.businessName ?? ""
                    let ok = await teamStore.recordPayment(
                        memberId: member.id,
                        ownerId: ownerId,
                        amount: amount,
                        notes: notes,
                        businessName: biz
                    )
                    if ok {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        await refreshPayments()
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showJobFromHistory) {
                if let jobId = selectedJobForDetail {
                    NavigationStack {
                        JobDetailView(jobId: jobId)
                    }
                    .environment(jobsStore)
                    .environment(clientsStore)
                    .environment(teamStore)
                }
            }
            .sheet(isPresented: $showFullHistory) {
                MemberFullHistoryView(
                    member: member,
                    payments: payments,
                    initialTab: fullHistoryInitialTab
                )
                .environment(jobsStore)
                .environment(clientsStore)
                .environment(teamStore)
            }
        }
        .onAppear {
            Task { await refreshPayments() }
        }
    }

    // MARK: - Profile Card

    private var memberProfileCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(member.avatarTone.backgroundColor)
                        .frame(width: 72, height: 72)
                    Text(member.initials.isEmpty ? "?" : member.initials)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(member.avatarTone.foregroundColor)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(isEditing ? localName : member.name)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(member.status))
                                    .frame(width: 7, height: 7)
                                Text(member.status.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(member.role.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.sweeplyAccent.opacity(0.12), in: Capsule())
                    }

                    Text("Member since %@".translated(with: member.addedAt.formatted(date: .abbreviated, time: .omitted)))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.72))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()

            if isEditing {
                contactEditRow(label: "Name".translated(), systemImage: "person") {
                    TextField("Full name".translated(), text: $localName)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                }
                Divider().padding(.leading, 52)
            }

            contactRow(label: "Email".translated(), value: member.email, systemImage: "envelope") {
                if isEditing {
                    TextField("email@example.com".translated(), text: $localEmail)
                        .font(.system(size: 15))
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } else {
                    Text(member.email.isEmpty ? "Not set".translated() : member.email)
                        .font(.system(size: 15))
                        .foregroundStyle(member.email.isEmpty ? Color.sweeplyTextSub : Color.primary)
                        .lineLimit(1)
                }
            }

            Divider().padding(.leading, 52)

            contactRow(label: "Phone".translated(), value: member.phone, systemImage: "phone") {
                if isEditing {
                    TextField("(555) 000-0000".translated(), text: $localPhone)
                        .font(.system(size: 15))
                        .keyboardType(.phonePad)
                } else {
                    Text(member.phone.isEmpty ? "Not set".translated() : member.phone)
                        .font(.system(size: 15))
                        .foregroundStyle(member.phone.isEmpty ? Color.sweeplyTextSub : Color.primary)
                }
            }

            Divider().padding(.leading, 52)

            if isEditing && hasContactChanges {
                Divider()
                Button {
                    Task { await saveContact() }
                } label: {
                    Group {
                        if isSavingContact {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Text("Save Contact Info".translated())
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                }
                .disabled(isSavingContact)
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.18), value: isEditing)
        .animation(.easeInOut(duration: 0.18), value: hasContactChanges)
    }

    private func contactRow<Content: View>(
        label: String,
        value: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 52, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing && !value.isEmpty {
                UIPasteboard.general.string = value
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func contactEditRow<Content: View>(
        label: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 52, alignment: .leading)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Performance Card

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS MONTH".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("Performance Overview".translated())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Divider()

            HStack(spacing: 0) {
                perfStatCell(value: "\(monthJobCount)", label: "Assigned".translated())
                perfDivider
                perfStatCell(value: "\(monthDoneCount)", label: "Completed".translated())
                perfDivider
                perfStatCell(value: "\(upcomingCount)", label: "Upcoming".translated())
                perfDivider
                perfStatCell(value: monthEarned.currencyWithoutTrailingZeros, label: "Earned".translated())
            }
            .padding(.vertical, 14)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func perfStatCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
    }

    private var perfDivider: some View {
        Rectangle().fill(Color.sweeplyBorder).frame(width: 1, height: 36)
    }

    // MARK: - Pay Setup Card

    private var paySetupCard: some View {
        let m = currentMember
        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAY SETUP".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text(m.payRateEnabled ? m.payRateType.displayName : "Not configured")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(paySetupSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showPaySetup = true
                } label: {
                    Text(m.payRateEnabled ? "Edit".translated() : "Set Up".translated())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.sweeplyNavy)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Per-job rate breakdown (read-only)
            if m.payRateEnabled && m.payRateType == .perJob && !m.serviceRates.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(m.serviceRates.filter { $0.value > 0 }.sorted { $0.key < $1.key }.enumerated()), id: \.element.key) { idx, entry in
                        HStack {
                            Text(entry.key)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyNavy)
                            Spacer()
                            Text(entry.value.currency)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyAccent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        if idx < m.serviceRates.filter({ $0.value > 0 }).count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color.sweeplyAccent.opacity(0.04))
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        .sheet(isPresented: $showPaySetup) {
            MemberPaySetupView(member: member)
                .environment(teamStore)
        }
    }

    // MARK: - Combined History Card (Job History + Payment History)

    private var historyCard: some View {
        VStack(spacing: 0) {
            // Header with tab switcher
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(historyTab == .jobs ? "JOB HISTORY" : "PAYMENT HISTORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                        .animation(.none, value: historyTab)
                    Text(historyTab == .jobs ? "Work this cleaner has done" : "Payments you've recorded")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .animation(.none, value: historyTab)
                }
                Spacer()

                // Compact pill switcher
                HStack(spacing: 0) {
                    tabPillButton("Jobs".translated(), isActive: historyTab == .jobs) {
                        withAnimation(.easeInOut(duration: 0.18)) { historyTab = .jobs }
                    }
                    tabPillButton("Payments".translated(), isActive: historyTab == .payments) {
                        withAnimation(.easeInOut(duration: 0.18)) { historyTab = .payments }
                    }
                }
                .padding(3)
                .background(Color.sweeplyBackground)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Content — switches between job history and payment history
            if historyTab == .jobs {
                jobHistoryContent
            } else {
                paymentHistoryContent
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func tabPillButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color.sweeplyTextSub)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? Color.sweeplyNavy : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Job History Content

    @ViewBuilder
    private var jobHistoryContent: some View {
        if memberJobHistory.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "briefcase")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
                Text("No jobs assigned yet".translated())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            let displayJobs = Array(memberJobHistory.prefix(10))
            let hasMore = memberJobHistory.count > 10
            VStack(spacing: 0) {
                ForEach(Array(displayJobs.enumerated()), id: \.element.id) { idx, job in
                    jobHistoryRow(job)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedJobForDetail = job.id
                            showJobFromHistory = true
                        }
                    if idx < displayJobs.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
                if hasMore {
                    Divider()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        fullHistoryInitialTab = .jobs
                        showFullHistory = true
                    } label: {
                        HStack {
                            Text(String(format: "View All %d Jobs".translated(), memberJobHistory.count))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Payment History Content

    @ViewBuilder
    private var paymentHistoryContent: some View {
        if isLoadingPayments {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if payments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
                Text("No payments recorded yet".translated())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text("Tap Record to log a payment".translated())
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            let displayPayments = Array(payments.prefix(10))
            let hasMorePayments = payments.count > 10
            VStack(spacing: 0) {
                ForEach(Array(displayPayments.enumerated()), id: \.element.id) { idx, payment in
                    paymentRow(payment)
                    if idx < displayPayments.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            if hasMorePayments {
                Divider()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    fullHistoryInitialTab = .payments
                    showFullHistory = true
                } label: {
                    HStack {
                        Text(String(format: "View All %d Payments".translated(), payments.count))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            Divider()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showRecordPayment = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Record Payment".translated())
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.sweeplyNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Job History Card (kept for reference, now replaced by historyCard)

    private var jobHistoryCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOB HISTORY".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("Work this cleaner has done".translated())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
                Text("%d total".translated(with: memberJobHistory.count))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if memberJobHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
                    Text("No jobs assigned yet".translated())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text("Jobs will appear here once %@ is assigned work".translated(with: member.name.components(separatedBy: " ").first ?? member.name))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(memberJobHistory.enumerated()), id: \.element.id) { idx, job in
                        jobHistoryRow(job)
                        if idx < memberJobHistory.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func jobHistoryRow(_ job: Job) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 3) {
                Text(job.date.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(job.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(job.serviceType.rawValue.translated())
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                    if !job.address.isEmpty {
                        Text("·")
                            .foregroundStyle(Color.sweeplyBorder)
                        Text(cityFromAddress(job.address))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(job.price.currency)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                StatusBadge(status: job.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var memberJobHistory: [Job] {
        jobsStore.jobs
            .filter { $0.isAssigned(to: member.id) && $0.status != .cancelled }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Payment History Card

    private var paymentHistoryCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAYMENT HISTORY".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("Payments you've recorded".translated())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showRecordPayment = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Record".translated())
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.sweeplyNavy)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if isLoadingPayments {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if payments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
                    Text("No payments recorded yet".translated())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text(String(format: "Tap Record to log a payment to %@".translated(), member.name.components(separatedBy: " ").first ?? member.name))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(payments.enumerated()), id: \.element.id) { idx, payment in
                        paymentRow(payment)
                        if idx < payments.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func paymentRow(_ payment: TeamMemberPayment) -> some View {
        let (method, desc) = parsePaymentDetails(from: payment.notes)

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.amount.currency)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(payment.paidAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                if !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let method {
                Text(method.rawValue.translated())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.sweeplyAccent.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Status Actions Card

    private var statusActionsCard: some View {
        VStack(spacing: 0) {
            if member.status == .invited {
                actionRow(title: "Resend Invite".translated(), icon: "paperplane", color: Color.sweeplyAccent) {
                    let biz = (profileStore.profile?.businessName ?? "").isEmpty ? "Your team" : (profileStore.profile?.businessName ?? "")
                    inviteMessage = "Hi \(member.name), \(biz) has invited you to join their Sweeply team. Download the Sweeply app and you're all set!"
                    showShareSheet = true
                }
                Divider().padding(.leading, 52)
                actionRow(title: "Mark as Active".translated(), icon: "checkmark.circle", color: Color.sweeplySuccess) {
                    Task {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let ok = await teamStore.updateStatus(id: member.id, status: .active)
                        if ok {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                }
            } else if member.status == .inactive {
                actionRow(title: "Mark as Active".translated(), icon: "checkmark.circle", color: Color.sweeplySuccess) {
                    Task {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let ok = await teamStore.updateStatus(id: member.id, status: .active)
                        if ok {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                }
            } else if member.status == .active {
                actionRow(title: "Mark as Inactive".translated(), icon: "moon.circle", color: Color.sweeplyTextSub) {
                    Task {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let ok = await teamStore.updateStatus(id: member.id, status: .inactive)
                        if ok {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                }
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func actionRow(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyBorder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Remove Button

    private var removeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.minus")
                Text("Remove from Team".translated())
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.sweeplyDestructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.sweeplyDestructive.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyDestructive.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Job Stats

    private var allMemberJobs: [Job] {
        jobsStore.jobs.filter { $0.isAssigned(to: member.id) && $0.status != .cancelled }
    }

    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    private var monthJobs: [Job] { allMemberJobs.filter { $0.date >= monthStart } }
    private var monthJobCount: Int { monthJobs.count }
    private var monthDoneCount: Int { monthJobs.filter { $0.status == .completed }.count }
    private var monthEarned: Double { monthJobs.filter { $0.status == .completed }.reduce(0) { $0 + $1.price } }
    private var upcomingCount: Int {
        allMemberJobs.filter { ($0.status == .scheduled || $0.status == .inProgress) && $0.date >= Date() }.count
    }

    // MARK: - Actions

    @MainActor
    private func saveContact() async {
        isSavingContact = true
        defer { isSavingContact = false }
        let ok = await teamStore.updateMember(
            id: member.id,
            name: localName.trimmingCharacters(in: .whitespaces),
            email: localEmail.trimmingCharacters(in: .whitespaces),
            phone: localPhone.trimmingCharacters(in: .whitespaces),
            role: member.role
        )
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { isEditing = false }
        }
    }

    private func refreshPayments() async {
        guard let ownerId = session.userId else { return }
        isLoadingPayments = true
        payments = await teamStore.loadPayments(memberId: member.id, ownerId: ownerId)
        isLoadingPayments = false
    }

    // MARK: - Payment Note Parser

    private func parsePaymentDetails(from notes: String) -> (PaymentMethod?, String) {
        for method in PaymentMethod.allCases {
            let prefix = method.rawValue + " · "
            if notes.hasPrefix(prefix) {
                return (method, String(notes.dropFirst(prefix.count)))
            }
            if notes == method.rawValue {
                return (method, "")
            }
        }
        return (nil, notes)
    }

    // MARK: - Status Color

    private func statusColor(_ status: TeamMemberStatus) -> Color {
        switch status {
        case .active:   return Color.sweeplySuccess
        case .invited:  return Color.sweeplyWarning
        case .inactive: return Color.sweeplyTextSub.opacity(0.5)
        }
    }
}

// MARK: - PayRateType Helpers

private extension PayRateType {
    var shortLabel: String {
        switch self {
        case .perJob:  return "Per Job".translated()
        case .perDay:  return "Per Day".translated()
        case .perWeek: return "Per Week".translated()
        case .custom:  return "Custom".translated()
        }
    }

    var perLabel: String {
        switch self {
        case .perJob:  return "job".translated()
        case .perDay:  return "day".translated()
        case .perWeek: return "week".translated()
        case .custom:  return "arrangement".translated()
        }
    }
}

// MARK: - RecordPaymentSheet

struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let member: TeamMember
    let onRecord: (Double, String) async -> Void

    @State private var amountText = ""
    @State private var notes = ""
    @State private var selectedMethod: PaymentMethod = .cash
    @State private var isRecording = false

    private var amount: Double { Double(amountText) ?? 0 }
    private var canRecord: Bool { amount > 0 && !isRecording }

    private var composedNotes: String {
        let base = "\(selectedMethod.rawValue)"
        return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? base
            : "\(base) · \(notes.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.sweeplyBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 20)

            // Header
            VStack(spacing: 4) {
                Text("Record Payment".translated())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("To %@".translated(with: member.name))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.bottom, 28)

            // Amount
            VStack(spacing: 6) {
                Text("AMOUNT".translated())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)
                HStack(alignment: .center, spacing: 4) {
                    Text("$".translated())
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(amount > 0 ? Color.sweeplyNavy : Color.sweeplyBorder)
                    TextField("0.00", text: $amountText)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            VStack(spacing: 20) {
                // Pay method
                VStack(alignment: .leading, spacing: 10) {
                    Text("PAY VIA".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PaymentMethod.allCases, id: \.self) { method in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.15)) { selectedMethod = method }
                                } label: {
                                    Text(method.rawValue.translated())
                                        .font(.system(size: 14, weight: selectedMethod == method ? .semibold : .medium))
                                        .foregroundStyle(selectedMethod == method ? .white : Color.sweeplyNavy)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 9)
                                        .background(selectedMethod == method ? Color.sweeplyNavy : Color.sweeplyBackground)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(selectedMethod == method ? Color.clear : Color.sweeplyBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTES (OPTIONAL)".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)

                    TextField("e.g. Week of Apr 21".translated(), text: $notes)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(Color.sweeplyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // CTA
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isRecording = true
                Task {
                    await onRecord(amount, composedNotes)
                    isRecording = false
                    dismiss()
                }
            } label: {
                Group {
                    if isRecording {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else {
                        Text(amount > 0 ? "Record %@".translated(with: amount.currency) : "Record Payment".translated())
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(canRecord ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: canRecord ? Color.sweeplyNavy.opacity(0.22) : .clear, radius: 8, x: 0, y: 4)
            }
            .disabled(!canRecord)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color.sweeplySurface.ignoresSafeArea())
    }
}

// MARK: - InviteMemberSheet

struct InviteMemberSheet: View {
    @Environment(TeamStore.self)    private var teamStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss)          private var dismiss

    let ownerId: UUID

    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email     = ""
    @State private var phone     = ""
    @State private var role      = TeamRole.member
    @State private var isSaving  = false
    @State private var showShareSheet    = false
    @State private var inviteMessage     = ""
    @State private var selectedAvatarTone: ClientAvatarTone = .slate
    @State private var showAvatarTonePicker = false

    // Pre-generate the UUID so we can save the avatar tone with the right key
    private let newMemberId = UUID()

    private var previewInitials: String {
        let f = firstName.prefix(1).uppercased()
        let l = lastName.prefix(1).uppercased()
        return f + l
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Avatar ───────────────────────────────────────────
                        VStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAvatarTonePicker.toggle()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(selectedAvatarTone.backgroundColor)
                                        .frame(width: 72, height: 72)
                                    if previewInitials.isEmpty {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 26, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.6))
                                    } else {
                                        Text(previewInitials)
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundStyle(selectedAvatarTone.foregroundColor)
                                    }
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    ZStack {
                                        Circle().fill(Color.sweeplyBackground).frame(width: 22, height: 22)
                                        Image(systemName: "paintpalette.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyNavy)
                                    }
                                    .offset(x: 2, y: 2)
                                }
                            }
                            .buttonStyle(.plain)

                            Text("Tap to choose color".translated())
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                        // ── Color picker (expands on avatar tap) ─────────────
                        if showAvatarTonePicker {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                ForEach(ClientAvatarTone.allCases, id: \.rawValue) { tone in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedAvatarTone = tone
                                            showAvatarTonePicker = false
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(tone.backgroundColor)
                                                .frame(width: 44, height: 44)
                                            if selectedAvatarTone == tone {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(tone.foregroundColor)
                                            }
                                        }
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    selectedAvatarTone == tone
                                                        ? Color.sweeplyNavy : Color.clear,
                                                    lineWidth: 2
                                                )
                                                .padding(-3)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }

                        // ── Fields ───────────────────────────────────────────
                        VStack(spacing: 0) {
                            fieldRow(label: "First".translated()) {
                                TextField("Jane".translated(), text: $firstName)
                                    .font(.system(size: 15))
                                    .autocorrectionDisabled()
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Last".translated()) {
                                TextField("Doe".translated(), text: $lastName)
                                    .font(.system(size: 15))
                                    .autocorrectionDisabled()
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Email".translated()) {
                                TextField("email@example.com", text: $email)
                                    .font(.system(size: 15))
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Phone".translated()) {
                                TextField("(555) 000-0000", text: $phone)
                                    .font(.system(size: 15))
                                    .keyboardType(.phonePad)
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Role".translated()) {
                                Picker("Role".translated(), selection: $role) {
                                    ForEach(TeamRole.allCases.filter { $0 != .owner }, id: \.self) { r in
                                        Text(r.displayName).tag(r)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 160)
                            }
                        }
                        .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))

                        // ── Save button ──────────────────────────────────────
                        Button {
                            Task { await addAndInvite() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "person.badge.plus")
                                    Text("Add & Share Invite".translated())
                                }
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canSave ? Color.sweeplyNavy : Color.sweeplyTextSub.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave || isSaving)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Invite Cleaner".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [inviteMessage])
            }
            .animation(.easeInOut(duration: 0.2), value: showAvatarTonePicker)
        }
    }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty && email.contains("@")
    }

    @MainActor
    private func addAndInvite() async {
        isSaving = true
        defer { isSaving = false }

        let fullName = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))"
            .trimmingCharacters(in: .whitespaces)

        let member = TeamMember(
            id: newMemberId,
            ownerId: ownerId,
            name: fullName,
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            phone: phone.trimmingCharacters(in: .whitespaces),
            role: role,
            status: .invited,
            addedAt: Date()
        )

        // Persist avatar tone before network call so it's ready immediately
        TeamMemberAvatarStyle.save(selectedAvatarTone, for: newMemberId)

        let success = await teamStore.add(member)
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let biz = (profileStore.profile?.businessName ?? "").isEmpty
                ? "Your team"
                : (profileStore.profile?.businessName ?? "")
            inviteMessage = "Hi \(fullName), \(biz) has invited you to join their Sweeply team as \(role.displayName). Download the Sweeply app and you're all set!"
            showShareSheet = true
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 56, alignment: .leading)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Member Full History View

struct MemberFullHistoryView: View {
    @Environment(\.dismiss)          private var dismiss
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(TeamStore.self)     private var teamStore

    let member: TeamMember
    let payments: [TeamMemberPayment]
    let initialTab: MemberDetailView.HistoryTab

    @State private var selectedTab: MemberDetailView.HistoryTab
    @State private var selectedJobId: UUID? = nil
    @State private var showJobDetail = false

    init(member: TeamMember, payments: [TeamMemberPayment], initialTab: MemberDetailView.HistoryTab) {
        self.member = member
        self.payments = payments
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    private var memberJobHistory: [Job] {
        jobsStore.jobs
            .filter { $0.isAssigned(to: member.id) && $0.status != .cancelled }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab switcher
                HStack(spacing: 0) {
                    tabPill("Jobs (\(memberJobHistory.count))", isActive: selectedTab == .jobs) {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = .jobs }
                    }
                    tabPill("Payments (\(payments.count))", isActive: selectedTab == .payments) {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = .payments }
                    }
                }
                .padding(3)
                .background(Color.sweeplyBackground)
                .clipShape(Capsule())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                ScrollView(showsIndicators: false) {
                    if selectedTab == .jobs {
                        jobsContent
                    } else {
                        paymentsContent
                    }
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyNavy)
                }
            }
        }
        .sheet(isPresented: $showJobDetail) {
            if let jobId = selectedJobId {
                NavigationStack {
                    JobDetailView(jobId: jobId)
                }
                .environment(jobsStore)
                .environment(clientsStore)
                .environment(teamStore)
            }
        }
    }

    // MARK: Jobs content

    @ViewBuilder
    private var jobsContent: some View {
        if memberJobHistory.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "briefcase")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                Text("No jobs assigned yet".translated())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(Array(memberJobHistory.enumerated()), id: \.element.id) { idx, job in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedJobId = job.id
                        showJobDetail = true
                    } label: {
                        fullJobRow(job)
                    }
                    .buttonStyle(.plain)

                    if idx < memberJobHistory.count - 1 {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: Payments content

    @ViewBuilder
    private var paymentsContent: some View {
        if payments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                Text("No payments recorded yet".translated())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(payments.enumerated()), id: \.element.id) { idx, payment in
                    fullPaymentRow(payment)
                    if idx < payments.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: Row views

    private func fullJobRow(_ job: Job) -> some View {
        HStack(spacing: 12) {
            // Date block
            VStack(alignment: .center, spacing: 2) {
                Text(job.date.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(job.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                Text(job.serviceType.rawValue.translated())
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(job.price.currency)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                StatusBadge(status: job.status)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fullPaymentRow(_ payment: TeamMemberPayment) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.amount.currency)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(payment.paidAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                if !payment.notes.isEmpty {
                    Text(payment.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func tabPill(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color.sweeplyTextSub)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? Color.sweeplyNavy : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
