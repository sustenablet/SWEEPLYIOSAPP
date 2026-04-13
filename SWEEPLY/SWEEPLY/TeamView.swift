import SwiftUI

// MARK: - TeamView

struct TeamView: View {
    @Environment(TeamStore.self)   private var teamStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)  private var session

    @State private var showInvite = false
    @State private var isRemoving = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                if teamStore.isLoading && teamStore.members.isEmpty {
                    ProgressView()
                        .tint(Color.sweeplyNavy)
                } else {
                    List {
                        // Owner section
                        Section {
                            ownerRow
                        } header: {
                            sectionHeader("Owner")
                        }
                        .listRowBackground(Color.sweeplySurface)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

                        // Cleaners section
                        Section {
                            let cleaners = teamStore.members.filter { $0.role == .member }
                            if cleaners.isEmpty {
                                emptyCleanersRow
                            } else {
                                ForEach(cleaners) { member in
                                    TeamMemberRow(member: member)
                                        .listRowBackground(Color.sweeplySurface)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                Task { await teamStore.remove(id: member.id) }
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        } header: {
                            sectionHeader("Cleaners")
                        }
                        .listRowBackground(Color.sweeplySurface)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.sweeplyBackground)
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
        }
    }

    // MARK: Owner row

    private var ownerRow: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy.gradient)
                    .frame(width: 44, height: 44)
                Text(ownerInitials)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text((profileStore.profile?.businessName ?? "").isEmpty ? "You" : (profileStore.profile?.businessName ?? ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Account owner")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            roleBadge("Owner", color: Color.sweeplyNavy)
        }
        .padding(.vertical, 12)
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

    // MARK: Empty cleaners

    private var emptyCleanersRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
            Text("No cleaners yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Tap Invite to add your first cleaner")
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowBackground(Color.sweeplySurface)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
            .padding(.top, 4)
    }

    private func roleBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}

// MARK: - TeamMemberRow

struct TeamMemberRow: View {
    let member: TeamMember

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.gradient)
                    .frame(width: 44, height: 44)
                Text(member.initials.isEmpty ? "?" : member.initials)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

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

            VStack(alignment: .trailing, spacing: 4) {
                roleBadge("Cleaner", color: Color.sweeplyAccent)
                statusDot(member.status)
            }
        }
        .padding(.vertical, 12)
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

// MARK: - InviteMemberSheet

struct InviteMemberSheet: View {
    @Environment(TeamStore.self)    private var teamStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss)         private var dismiss

    let ownerId: UUID

    @State private var name  = ""
    @State private var email = ""
    @State private var role  = TeamRole.member
    @State private var isSaving = false
    @State private var showShareSheet = false
    @State private var inviteMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Form card
                        VStack(spacing: 0) {
                            fieldRow(label: "Name") {
                                TextField("Full name", text: $name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.primary)
                            }

                            Divider()
                                .padding(.leading, 20)
                                .background(Color.sweeplyBorder)

                            fieldRow(label: "Email") {
                                TextField("email@example.com", text: $email)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.primary)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }

                            Divider()
                                .padding(.leading, 20)
                                .background(Color.sweeplyBorder)

                            fieldRow(label: "Role") {
                                Picker("Role", selection: $role) {
                                    ForEach(TeamRole.allCases, id: \.self) { r in
                                        Text(r.displayName).tag(r)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 160)
                            }
                        }
                        .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 14))

                        // Add button
                        Button {
                            Task { await addAndInvite() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.85)
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
                                canSave
                                ? Color.sweeplyNavy
                                : Color.sweeplyTextSub.opacity(0.3),
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
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@")
    }

    @MainActor
    private func addAndInvite() async {
        isSaving = true
        defer { isSaving = false }

        let member = TeamMember(
            ownerId: ownerId,
            name: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            role: role,
            status: .invited,
            addedAt: Date()
        )

        let success = await teamStore.add(member)
        if success {
            let biz = (profileStore.profile?.businessName ?? "").isEmpty ? "Your team" : (profileStore.profile?.businessName ?? "")
            inviteMessage = "Hi \(member.name), \(biz) has invited you to join their Sweeply team as \(role.displayName). Download the Sweeply app and you're all set!"
            showShareSheet = true
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 60, alignment: .leading)
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
