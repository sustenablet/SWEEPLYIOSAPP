import SwiftUI

// MARK: - TeamView

struct TeamView: View {
    @Environment(TeamStore.self)    private var teamStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session

    @State private var showInvite    = false
    @State private var editingMember : TeamMember? = nil
    @State private var deleteTarget  : TeamMember? = nil
    @State private var showDeleteConfirm = false

    @Environment(\.dismiss) private var dismiss

    private var cleaners: [TeamMember]  { teamStore.members.filter { $0.role == .member } }
    private var activeCount: Int   { teamStore.members.filter { $0.status == .active   }.count }
    private var invitedCount: Int  { teamStore.members.filter { $0.status == .invited  }.count }
    private var inactiveCount: Int { teamStore.members.filter { $0.status == .inactive }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Pending invites for this user
                        if !session.pendingInvites.isEmpty {
                            pendingInvitesSection
                        }

                        // Stats strip
                        statsStrip

                        // Error banner
                        if let err = teamStore.lastError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyDestructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                        }

                        // Owner card
                        memberSection(title: "Owner") {
                            ownerRow
                        }

                        // Cleaners section
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
            .sheet(item: $editingMember) { member in
                EditMemberSheet(member: member)
                    .environment(teamStore)
                    .environment(profileStore)
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

    // MARK: - Pending invites (for current user)

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
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sweeplyAccent.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Stats strip

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
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1, height: 36)
    }

    // MARK: - Section wrapper

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

    // MARK: - Owner row

    private var ownerRow: some View {
        HStack(spacing: 14) {
            avatarCircle(
                initials: ownerInitials,
                color: Color.sweeplyNavy
            )

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

    // MARK: - Member row

    private func memberRow(_ member: TeamMember) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editingMember = member
        } label: {
            HStack(spacing: 14) {
                avatarCircle(initials: member.initials.isEmpty ? "?" : member.initials,
                             color: Color.sweeplyAccent)

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

    // MARK: - Empty state

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

    // MARK: - Shared helpers

    private func avatarCircle(initials: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.gradient)
                .frame(width: 44, height: 44)
            Text(initials)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
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

// MARK: - EditMemberSheet

struct EditMemberSheet: View {
    @Environment(TeamStore.self)    private var teamStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss)          private var dismiss

    let member: TeamMember

    @State private var name     : String
    @State private var email    : String
    @State private var phone    : String
    @State private var role     : TeamRole
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet    = false
    @State private var inviteMessage     = ""

    init(member: TeamMember) {
        self.member = member
        _name  = State(initialValue: member.name)
        _email = State(initialValue: member.email)
        _phone = State(initialValue: member.phone)
        _role  = State(initialValue: member.role)
    }

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespaces) != member.name ||
        email.trimmingCharacters(in: .whitespaces).lowercased() != member.email ||
        phone.trimmingCharacters(in: .whitespaces) != member.phone ||
        role != member.role
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Avatar + name hero
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.sweeplyAccent.gradient)
                                    .frame(width: 64, height: 64)
                                Text(member.initials.isEmpty ? "?" : member.initials)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            statusDot(member.status)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Form card
                        VStack(spacing: 0) {
                            editFieldRow(label: "Name") {
                                TextField("Full name", text: $name)
                                    .font(.system(size: 15))
                            }

                            Divider().padding(.leading, 80)

                            editFieldRow(label: "Email") {
                                TextField("email@example.com", text: $email)
                                    .font(.system(size: 15))
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }

                            Divider().padding(.leading, 80)

                            editFieldRow(label: "Phone") {
                                TextField("(555) 000-0000", text: $phone)
                                    .font(.system(size: 15))
                                    .keyboardType(.phonePad)
                            }

                            Divider().padding(.leading, 80)

                            editFieldRow(label: "Role") {
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

                        // Status actions
                        VStack(spacing: 10) {
                            if member.status == .invited || member.status == .inactive {
                                actionButton(
                                    title: "Mark as Active",
                                    icon: "checkmark.circle",
                                    color: Color.sweeplySuccess
                                ) {
                                    Task {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        let ok = await teamStore.updateStatus(id: member.id, status: .active)
                                        if ok {
                                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                                            dismiss()
                                        }
                                    }
                                }
                            }

                            if member.status == .active {
                                actionButton(
                                    title: "Mark as Inactive",
                                    icon: "moon.circle",
                                    color: Color.sweeplyTextSub
                                ) {
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

                            if member.status == .invited {
                                actionButton(
                                    title: "Resend Invite",
                                    icon: "paperplane",
                                    color: Color.sweeplyAccent
                                ) {
                                    let biz = (profileStore.profile?.businessName ?? "").isEmpty
                                        ? "Your team"
                                        : (profileStore.profile?.businessName ?? "")
                                    inviteMessage = "Hi \(member.name), \(biz) has invited you to join their Sweeply team as \(member.role.displayName). Download the Sweeply app and you're all set!"
                                    showShareSheet = true
                                }
                            }
                        }

                        // Remove from team
                        Button {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.minus")
                                Text("Remove from Team")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyDestructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sweeplyDestructive.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.sweeplyDestructive.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Added date
                        Text("Added \(member.addedAt.formatted(date: .long, time: .omitted))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(hasChanges ? Color.sweeplyNavy : Color.sweeplyTextSub)
                        }
                    }
                    .disabled(!hasChanges || isSaving)
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
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let ok = await teamStore.updateMember(
            id: member.id,
            name: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            phone: phone.trimmingCharacters(in: .whitespaces),
            role: role
        )
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }

    private func editFieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusDot(_ status: TeamMemberStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status == .active ? Color.sweeplySuccess : status == .inactive ? Color.sweeplyWarning : Color.sweeplyTextSub.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
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
