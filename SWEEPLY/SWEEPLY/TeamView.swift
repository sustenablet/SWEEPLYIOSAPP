import SwiftUI

// MARK: - TeamView

struct TeamView: View {
    @Environment(TeamStore.self)           private var teamStore
    @Environment(ProfileStore.self)        private var profileStore
    @Environment(AppSession.self)          private var session

    @State private var showInvite         = false
    @State private var selectedMember  : TeamMember? = nil
    @State private var deleteTarget    : TeamMember? = nil
    @State private var showDeleteConfirm = false

    @AppStorage("newFeatureDot_teamBanner") private var dotTeamBanner = false

    @Environment(\.dismiss) private var dismiss

    private var cleaners: [TeamMember]  { teamStore.members.filter { $0.role == .member } }
    private var activeCount: Int        { teamStore.members.filter { $0.status == .active   }.count }
    private var invitedCount: Int       { teamStore.members.filter { $0.status == .invited  }.count }
    private var inactiveCount: Int      { teamStore.members.filter { $0.status == .inactive }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if dotTeamBanner {
                            proUnlockBanner
                        }

                        if !session.pendingInvites.isEmpty {
                            pendingInvitesSection
                        }

                        statsStrip

                        if !session.activeMemberships.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("TEAMS".translated())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                    .tracking(0.8)

                                ForEach(session.activeMemberships) { (membership: TeamMembership) in
                                    HStack(spacing: 10) {
                                        Text(membership.businessName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyNavy)
                                            .lineLimit(1)

                                        Spacer(minLength: 8)

                                        Button {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            session.switchToMembership(membership)
                                        } label: {
                                            Text("Join".translated())
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 7)
                                                .background(Color.sweeplyAccent)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        if let err = teamStore.lastError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyDestructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                        }

                        memberSection(title: "Owner") { ownerRow }

                        memberSection(title: "Cleaners") {
                            if cleaners.isEmpty {
                                emptyCleanersState
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(cleaners.enumerated()), id: \.element.id) { idx, member in
                                        memberRow(member)
                                        if idx < cleaners.count - 1 {
                                            Divider().padding(.leading, 74)
                                        }
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 16)
                }
                .refreshable {
                    if let uid = session.userId {
                        await teamStore.load(ownerId: uid)
                    }
                }
            }
            .onAppear {
                if dotTeamBanner {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeInOut(duration: 0.3)) { dotTeamBanner = false }
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
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Invite".translated())
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Color.sweeplyNavy)
                    }
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

    // MARK: - Pro Unlock Banner

    private var proUnlockBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Team tools are unlocked".translated())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("Invite as many team members as your business needs.".translated())
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { dotTeamBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.22, green: 0.50, blue: 0.92), Color(red: 0.18, green: 0.42, blue: 0.80)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Pending Invites

    @State private var acceptingInviteId: UUID? = nil
    @State private var decliningInviteId: UUID? = nil

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEAM INVITES".translated())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.5)
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(session.pendingInvites) { invite in
                    pendingInviteCard(invite)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func pendingInviteCard(_ invite: PendingInvite) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sweeplyAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.businessName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("Invited you as %@".translated(with: invite.role.capitalized))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    decliningInviteId = invite.id
                    Task {
                        await session.declineInvite(memberId: invite.id)
                        decliningInviteId = nil
                    }
                } label: {
                    Text(decliningInviteId == invite.id ? "Declining…" : "Decline")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.sweeplyBorder.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(acceptingInviteId != nil || decliningInviteId != nil)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    acceptingInviteId = invite.id
                    Task {
                        await session.acceptInvite(memberId: invite.id)
                        acceptingInviteId = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        if acceptingInviteId == invite.id {
                            ProgressView().tint(.white).scaleEffect(0.75)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(acceptingInviteId == invite.id ? "Joining…" : "Accept")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.sweeplyAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(acceptingInviteId != nil || decliningInviteId != nil)
            }
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyAccent.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(value: "\(teamStore.members.count + 1)", label: "Total")
            statDivider
            statCell(value: "\(activeCount)", label: "Active")
            statDivider
            statCell(value: "\(invitedCount)", label: "Invited")
            statDivider
            statCell(value: "\(inactiveCount)", label: "Inactive")
        }
        .padding(.vertical, 14)
        .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.primary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.sweeplyBorder).frame(width: 1, height: 36)
    }

    // MARK: - Section Wrapper

    private func memberSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                .padding(.horizontal, 20)

            content()
                .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Owner Row

    private var ownerRow: some View {
        HStack(spacing: 14) {
            avatarCircle(initials: ownerInitials, color: Color.sweeplyNavy)
            VStack(alignment: .leading, spacing: 2) {
                Text((profileStore.profile?.businessName ?? "").isEmpty
                     ? "You"
                     : (profileStore.profile?.businessName ?? ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Account owner".translated())
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            roleBadge("Owner", color: Color.sweeplyNavy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var ownerInitials: String {
        let name = profileStore.profile?.businessName ?? ""
        if name.isEmpty { return "ME" }
        return name.split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
    }

    // MARK: - Member Row

    private func memberRow(_ member: TeamMember) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedMember = member
        } label: {
            HStack(spacing: 14) {
                avatarCircle(initials: member.initials.isEmpty ? "?" : member.initials, color: Color.sweeplyAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 11))
                        Text(member.payRateDescription)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.sweeplySuccess)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    roleBadge("Cleaner", color: Color.sweeplyAccent)
                    statusDot(member.status)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyBorder)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = member
                showDeleteConfirm = true
            } label: {
                Label("Remove".translated(), systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyCleanersState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text("No cleaners yet".translated())
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Tap Invite to add your first cleaner".translated())
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Shared Helpers

    private func avatarCircle(initials: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color.gradient).frame(width: 44, height: 44)
            Text(initials).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
        }
    }

    private func roleBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    private func statusDot(_ status: TeamMemberStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status == .active ? Color.sweeplySuccess : Color.sweeplyTextSub.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyTextSub)
        }
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
        guard m.payRateEnabled else { return "Not configured" }
        let key = "memberPayMethod_\(m.id.uuidString)"
        let methodRaw = UserDefaults.standard.string(forKey: key) ?? ""
        let via = PaymentMethod(rawValue: methodRaw)?.rawValue ?? ""
        let viaSuffix = via.isEmpty ? "" : " · \(via)"
        switch m.payRateType {
        case .perJob:
            let count = m.serviceRates.filter { $0.value > 0 }.count
            return count > 0 ? "\(count) service rate\(count == 1 ? "" : "s") · Per Job\(viaSuffix)" : "Per Job\(viaSuffix)"
        case .perDay:   return "\(m.payRateAmount.currency) per day\(viaSuffix)"
        case .perWeek:  return "\(m.payRateAmount.currency) per week\(viaSuffix)"
        case .custom:   return "Custom\(viaSuffix)"
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
                    profileHeader
                    contactCard
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

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.gradient)
                    .frame(width: 76, height: 76)
                Text(member.initials.isEmpty ? "?" : member.initials)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(member.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(member.status))
                        .frame(width: 7, height: 7)
                    Text(member.status.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                Text("Member since %@".translated(with: member.addedAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .padding(.vertical, 20)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Contact Card

    private var contactCard: some View {
        VStack(spacing: 0) {
            // Name (only shown in edit mode — normally in header)
            if isEditing {
                contactEditRow(label: "Name", systemImage: "person") {
                    TextField("Full name", text: $localName)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                }
                Divider().padding(.leading, 52)
            }

            contactRow(label: "Email", value: member.email, systemImage: "envelope") {
                if isEditing {
                    TextField("email@example.com", text: $localEmail)
                        .font(.system(size: 15))
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } else {
                    Text(member.email.isEmpty ? "Not set" : member.email)
                        .font(.system(size: 15))
                        .foregroundStyle(member.email.isEmpty ? Color.sweeplyTextSub : Color.primary)
                        .lineLimit(1)
                }
            }

            Divider().padding(.leading, 52)

            contactRow(label: "Phone", value: member.phone, systemImage: "phone") {
                if isEditing {
                    TextField("(555) 000-0000", text: $localPhone)
                        .font(.system(size: 15))
                        .keyboardType(.phonePad)
                } else {
                    Text(member.phone.isEmpty ? "Not set" : member.phone)
                        .font(.system(size: 15))
                        .foregroundStyle(member.phone.isEmpty ? Color.sweeplyTextSub : Color.primary)
                }
            }

            Divider().padding(.leading, 52)

            contactRow(label: "Role".translated(), value: "", systemImage: "briefcase") {
                HStack {
                    Spacer(minLength: 0)
                    Text("Cleaner".translated())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.sweeplyAccent, in: Capsule())
                }
            }

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
                perfStatCell(value: "\(monthJobCount)", label: "Assigned")
                perfDivider
                perfStatCell(value: "\(monthDoneCount)", label: "Completed")
                perfDivider
                perfStatCell(value: "\(upcomingCount)", label: "Upcoming")
                perfDivider
                perfStatCell(value: monthEarned.currencyWithoutTrailingZeros, label: "Earned")
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
                Text("\(memberJobHistory.count) total")
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
                    Text(job.serviceType.rawValue)
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
            .filter { $0.assignedMemberId == member.id && $0.status != .cancelled }
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
                Text(method.rawValue)
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
                actionRow(title: "Resend Invite", icon: "paperplane", color: Color.sweeplyAccent) {
                    let biz = (profileStore.profile?.businessName ?? "").isEmpty ? "Your team" : (profileStore.profile?.businessName ?? "")
                    inviteMessage = "Hi \(member.name), \(biz) has invited you to join their Sweeply team. Download the Sweeply app and you're all set!"
                    showShareSheet = true
                }
                Divider().padding(.leading, 52)
                actionRow(title: "Mark as Active", icon: "checkmark.circle", color: Color.sweeplySuccess) {
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
                actionRow(title: "Mark as Active", icon: "checkmark.circle", color: Color.sweeplySuccess) {
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
                actionRow(title: "Mark as Inactive", icon: "moon.circle", color: Color.sweeplyTextSub) {
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
        jobsStore.jobs.filter { $0.assignedMemberId == member.id && $0.status != .cancelled }
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
        case .perJob:  return "job"
        case .perDay:  return "day"
        case .perWeek: return "week"
        case .custom:  return "arrangement"
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
                Text("To \(member.name)".translated())
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
                                    Text(method.rawValue)
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

                    TextField("e.g. Week of Apr 21", text: $notes)
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
                        Text(amount > 0 ? "Record \(amount.currency)".translated() : "Record Payment".translated())
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

    @State private var name    = ""
    @State private var email   = ""
    @State private var phone   = ""
    @State private var role    = TeamRole.member
    @State private var isSaving = false
    @State private var showShareSheet = false
    @State private var inviteMessage  = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 0) {
                            fieldRow(label: "Name") {
                                TextField("Full name", text: $name)
                                    .font(.system(size: 15))
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Email") {
                                TextField("email@example.com", text: $email)
                                    .font(.system(size: 15))
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Phone") {
                                TextField("(555) 000-0000", text: $phone)
                                    .font(.system(size: 15))
                                    .keyboardType(.phonePad)
                            }

                            Divider().padding(.leading, 80)

                            fieldRow(label: "Role") {
                                Picker("Role", selection: $role) {
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
                    .padding(.top, 20)
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
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && email.contains("@")
    }

    @MainActor
    private func addAndInvite() async {
        isSaving = true
        defer { isSaving = false }

        let member = TeamMember(
            ownerId: ownerId,
            name: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            phone: phone.trimmingCharacters(in: .whitespaces),
            role: role,
            status: .invited,
            addedAt: Date()
        )

        let success = await teamStore.add(member)
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let biz = (profileStore.profile?.businessName ?? "").isEmpty
                ? "Your team"
                : (profileStore.profile?.businessName ?? "")
            inviteMessage = "Hi \(member.name), \(biz) has invited you to join their Sweeply team as \(role.displayName). Download the Sweeply app and you're all set!"
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
            .filter { $0.assignedMemberId == member.id && $0.status != .cancelled }
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
                Text(job.serviceType.rawValue)
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
