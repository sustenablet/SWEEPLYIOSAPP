import SwiftUI

// MARK: - TeamView

struct TeamView: View {
    @Environment(TeamStore.self)    private var teamStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session

    @State private var showInvite      = false
    @State private var selectedMember  : TeamMember? = nil
    @State private var deleteTarget    : TeamMember? = nil
    @State private var showDeleteConfirm = false

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
                        if !session.pendingInvites.isEmpty {
                            pendingInvitesSection
                        }

                        statsStrip

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
            .navigationTitle("My Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
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
                            Text("Invite")
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
                Button("Remove", role: .destructive) {
                    guard let target = deleteTarget else { return }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    Task { await teamStore.remove(id: target.id) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This will remove them from your roster. You can invite them again anytime.")
            }
        }
    }

    // MARK: - Pending Invites

    @State private var acceptingInviteId: UUID? = nil
    @State private var decliningInviteId: UUID? = nil

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEAM INVITES")
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
                    Text("Invited you as \(invite.role.capitalized)")
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
                Text("Account owner")
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
                    Text(member.email)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
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
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyCleanersState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text("No cleaners yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Tap Invite to add your first cleaner")
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
    @Environment(TeamStore.self)    private var teamStore
    @Environment(JobsStore.self)    private var jobsStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session
    @Environment(\.dismiss)          private var dismiss

    let member: TeamMember

    // Contact edit
    @State private var isEditing = false
    @State private var localName: String
    @State private var localEmail: String
    @State private var localPhone: String
    @State private var isSavingContact = false

    // Pay rate
    @State private var localRateEnabled: Bool
    @State private var localRateType: PayRateType
    @State private var localRateAmountText: String
    @State private var localPayMethod: PaymentMethod = .cash
    @State private var isSavingPayRate = false
    @State private var payRateSaved = false

    // Status / removal
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false
    @State private var inviteMessage = ""

    // Payment history
    @State private var payments: [TeamMemberPayment] = []
    @State private var isLoadingPayments = false
    @State private var showRecordPayment = false

    init(member: TeamMember) {
        self.member = member
        _localName = State(initialValue: member.name)
        _localEmail = State(initialValue: member.email)
        _localPhone = State(initialValue: member.phone)
        _localRateEnabled = State(initialValue: member.payRateEnabled)
        _localRateType = State(initialValue: member.payRateType)
        _localRateAmountText = State(initialValue: member.payRateAmount > 0 ? String(format: "%.2f", member.payRateAmount) : "")
    }

    // MARK: - Derived

    private var hasContactChanges: Bool {
        localName.trimmingCharacters(in: .whitespaces) != member.name ||
        localEmail.trimmingCharacters(in: .whitespaces) != member.email ||
        localPhone.trimmingCharacters(in: .whitespaces) != member.phone
    }

    private var parsedRateAmount: Double { Double(localRateAmountText) ?? 0 }

    private var hasPayRateChanges: Bool {
        localRateEnabled != member.payRateEnabled ||
        localRateType != member.payRateType ||
        abs(parsedRateAmount - member.payRateAmount) > 0.001
    }

    private var payRateSummary: String {
        guard localRateEnabled, parsedRateAmount > 0 else { return "" }
        let amount = parsedRateAmount.currency
        let via = localPayMethod.rawValue
        switch localRateType {
        case .perJob:  return "\(amount) per job · \(via)"
        case .perDay:  return "\(amount) per day · \(via)"
        case .perWeek: return "\(amount) per week · \(via)"
        case .custom:  return "Custom arrangement · \(via)"
        }
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
                    paymentHistoryCard
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
                    Button("Close") { dismiss() }
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
                Button("Remove", role: .destructive) {
                    Task {
                        let ok = await teamStore.remove(id: member.id)
                        if ok { dismiss() }
                    }
                }
            } message: {
                Text("You can invite them again anytime.")
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [inviteMessage])
            }
            .sheet(isPresented: $showRecordPayment) {
                RecordPaymentSheet(member: member) { amount, notes in
                    guard let ownerId = session.userId else { return }
                    let ok = await teamStore.recordPayment(
                        memberId: member.id,
                        ownerId: ownerId,
                        amount: amount,
                        notes: notes
                    )
                    if ok {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        await refreshPayments()
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            localPayMethod = loadPayMethod()
            Task { await refreshPayments() }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 10) {
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

                Text("Member since \(member.addedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
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

            HStack(spacing: 14) {
                Image(systemName: "briefcase")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
                    .frame(width: 24)
                Text("Role")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("Cleaner")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.sweeplyAccent, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if isEditing && hasContactChanges {
                Divider()
                Button {
                    Task { await saveContact() }
                } label: {
                    Group {
                        if isSavingContact {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Text("Save Contact Info")
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
                    Text("THIS MONTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("Performance Overview")
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
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAY SETUP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("How you pay this cleaner")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Spacer()
                Toggle("", isOn: $localRateEnabled)
                    .tint(Color.sweeplyAccent)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if localRateEnabled {
                Divider()

                // Pay type selector
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pay Type")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)

                    HStack(spacing: 8) {
                        ForEach(PayRateType.allCases, id: \.self) { type in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.15)) { localRateType = type }
                            } label: {
                                Text(type.shortLabel)
                                    .font(.system(size: 13, weight: localRateType == type ? .semibold : .medium))
                                    .foregroundStyle(localRateType == type ? .white : Color.sweeplyNavy)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(localRateType == type ? Color.sweeplyNavy : Color.sweeplyBackground)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(localRateType == type ? Color.clear : Color.sweeplyBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if localRateType != .custom {
                    Divider()

                    // Amount field
                    HStack(spacing: 10) {
                        Text("$")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                        TextField("0.00", text: $localRateAmountText)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text("per \(localRateType.perLabel)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider()

                // Pay method
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pay Via")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PaymentMethod.allCases, id: \.self) { method in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        localPayMethod = method
                                        savePayMethod(method)
                                    }
                                } label: {
                                    Text(method.rawValue)
                                        .font(.system(size: 13, weight: localPayMethod == method ? .semibold : .medium))
                                        .foregroundStyle(localPayMethod == method ? .white : Color.sweeplyNavy)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(localPayMethod == method ? Color.sweeplyAccent : Color.sweeplyBackground)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(localPayMethod == method ? Color.clear : Color.sweeplyBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if !payRateSummary.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyAccent)
                        Text(payRateSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.sweeplyAccent.opacity(0.05))
                }

                if hasPayRateChanges {
                    Divider()
                    Button {
                        Task { await savePayRate() }
                    } label: {
                        Group {
                            if isSavingPayRate {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            } else if payRateSaved {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Saved")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                            } else {
                                Text("Save Pay Setup")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplyNavy)
                    }
                    .disabled(isSavingPayRate)
                }
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: localRateEnabled)
        .animation(.easeInOut(duration: 0.15), value: hasPayRateChanges)
    }

    // MARK: - Payment History Card

    private var paymentHistoryCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAYMENT HISTORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                    Text("Payments you've recorded")
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
                        Text("Record")
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
                    Text("No payments recorded yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text("Tap Record to log a payment to \(member.name.components(separatedBy: " ").first ?? member.name)")
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
                Text("Remove from Team")
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

    @MainActor
    private func savePayRate() async {
        isSavingPayRate = true
        defer { isSavingPayRate = false }
        let ok = await teamStore.updatePayRate(
            id: member.id,
            rateType: localRateType,
            amount: localRateType == .custom ? 0 : parsedRateAmount,
            enabled: localRateEnabled
        )
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            payRateSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { payRateSaved = false }
        }
    }

    private func refreshPayments() async {
        guard let ownerId = session.userId else { return }
        isLoadingPayments = true
        payments = await teamStore.loadPayments(memberId: member.id, ownerId: ownerId)
        isLoadingPayments = false
    }

    // MARK: - Pay Method Persistence (AppStorage equivalent)

    private func loadPayMethod() -> PaymentMethod {
        let key = "memberPayMethod_\(member.id.uuidString)"
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        return PaymentMethod(rawValue: raw) ?? .cash
    }

    private func savePayMethod(_ method: PaymentMethod) {
        let key = "memberPayMethod_\(member.id.uuidString)"
        UserDefaults.standard.set(method.rawValue, forKey: key)
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
        case .perJob:  return "Per Job"
        case .perDay:  return "Per Day"
        case .perWeek: return "Per Week"
        case .custom:  return "Custom"
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
                Text("Record Payment")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("To \(member.name)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.bottom, 28)

            // Amount
            VStack(spacing: 6) {
                Text("AMOUNT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)
                HStack(alignment: .center, spacing: 4) {
                    Text("$")
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
                    Text("PAY VIA")
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
                    Text("NOTES (OPTIONAL)")
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
                        Text("Record \(amount > 0 ? amount.currency : "Payment")")
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
                                    Text("Add & Share Invite")
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
            .navigationTitle("Invite Cleaner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
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

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
