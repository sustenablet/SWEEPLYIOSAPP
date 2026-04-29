import SwiftUI

struct CleanerSettingsView: View {
    @Environment(\.dismiss)         private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session

    let membership: TeamMembership

    @State private var localProfile: UserProfile = MockData.profile
    @State private var baselineProfile: UserProfile = MockData.profile
    @State private var isSaving = false
    @State private var feedbackMessage: String?
    @State private var feedbackStyle: CleanerSettingsFeedbackStyle = .info
    @State private var showSignOutAlert = false

    private var hasUnsavedChanges: Bool {
        localProfile.fullName != baselineProfile.fullName ||
        localProfile.email != baselineProfile.email ||
        localProfile.phone != baselineProfile.phone
    }

    private var validationMessage: String? {
        if localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Full name is required.".translated()
        }
        let email = localProfile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || !email.contains("@") {
            return "Enter a valid email address.".translated()
        }
        return nil
    }

    private var canSave: Bool {
        !isSaving && validationMessage == nil && hasUnsavedChanges
    }

    private var avatarInitials: String {
        let parts = localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Avatar header ──────────────────────────────────
                    avatarHeader
                        .padding(.top, 28)
                        .padding(.bottom, 32)

                    // ── Group 1: Profile ───────────────────────────────
                    menuGroup {
                        NavigationLink(destination: profilePage) {
                            menuRowLabel(icon: "person.circle", title: "Profile".translated())
                        }
                        .buttonStyle(.plain)
                    }

                    groupDivider()

                    // ── Group 2: App / Support ─────────────────────────
                    menuGroup {
                        menuRow(icon: "questionmark.message", title: "Support".translated()) { }
                        rowDivider()
                        NavigationLink(destination: aboutPage) {
                            menuRowLabel(icon: "info.circle", title: "About".translated())
                        }
                        .buttonStyle(.plain)
                    }

                    groupDivider()

                    // ── Group 3: Account ───────────────────────────────
                    menuGroup {
                        menuRow(icon: "arrow.left.arrow.right",
                                title: "Switch to My Business".translated()) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            session.switchToOwnBusiness()
                            dismiss()
                        }
                        rowDivider()
                        menuRow(icon: "rectangle.portrait.and.arrow.right",
                                title: "Sign Out".translated(),
                                color: Color.sweeplyDestructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showSignOutAlert = true
                        }
                    }

                    Spacer().frame(height: 48)
                }
            }
            .background(Color.sweeplySurface.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .onAppear {
                if let p = profileStore.profile {
                    localProfile = p
                    baselineProfile = p
                }
            }
            .confirmationDialog("Sign out of Sweeply?".translated(), isPresented: $showSignOutAlert) {
                Button("Sign out".translated(), role: .destructive) {
                    Task { await session.signOut() }
                }
            } message: {
                Text("You'll need to sign in again to access your account.".translated())
            }
        }
    }

    // MARK: - Avatar Header

    private var avatarHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 76, height: 76)
                Text(avatarInitials)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 3) {
                let name = localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Text(membership.businessName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Menu Helpers

    @ViewBuilder
    private func menuGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.sweeplySurface)
    }

    @ViewBuilder
    private func menuRow(
        icon: String,
        title: String,
        color: Color = Color.sweeplyNavy,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            menuRowLabel(icon: icon, title: title, color: color)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menuRowLabel(
        icon: String,
        title: String,
        color: Color = Color.sweeplyNavy
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title.translated())
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.sweeplySurface)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Rectangle()
            .fill(Color.sweeplyBorder.opacity(0.6))
            .frame(height: 0.5)
            .padding(.leading, 64)
    }

    @ViewBuilder
    private func groupDivider() -> some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(height: 8)
            .background(Color.sweeplyBackground)
    }

    // MARK: - Sub-Pages

    @ViewBuilder
    private var profilePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileAvatarHeader
                if let msg = feedbackMessage {
                    feedbackBanner(message: msg, style: feedbackStyle).padding(.horizontal, 20)
                } else if let msg = validationMessage, hasUnsavedChanges {
                    feedbackBanner(message: msg, style: .warning).padding(.horizontal, 20)
                }
                profileSection.padding(.horizontal, 20)
            }
            .padding(.bottom, 48)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle("Profile".translated())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if hasUnsavedChanges {
                    Button(isSaving ? "Saving..." : "Save") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await saveChanges() }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSave ? Color.sweeplyAccent : Color.sweeplyTextSub)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var profileAvatarHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.sweeplyNavy).frame(width: 72, height: 72)
                Text(avatarInitials)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 3) {
                let name = localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    Text(name).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.sweeplyNavy)
                }
                Text(membership.businessName).font(.system(size: 13)).foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("PERSONAL INFO".translated())
            SectionCard {
                VStack(spacing: 14) {
                    SettingsField(label: "Full Name", text: $localProfile.fullName)
                    Divider()
                    SettingsField(label: "Email Address", text: $localProfile.email, keyboard: .emailAddress)
                    Divider()
                    SettingsField(label: "Phone Number", text: $localProfile.phone, keyboard: .phonePad)
                }
            }
            sectionLabel("TEAM".translated()).padding(.top, 16)
            SectionCard {
                HStack(spacing: 14) {
                    settingsIcon("building.2.fill", color: Color.sweeplyAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(membership.businessName)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Text(membership.role.capitalized)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var aboutPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("APP INFO")
                settingsGroup {
                    HStack(spacing: 14) {
                        settingsIcon("info.circle.fill", color: Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("Version".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .font(.system(size: 15, design: .monospaced)).foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().padding(.leading, 58)
                    HStack(spacing: 14) {
                        settingsIcon("hammer.fill", color: Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("Build".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                            .font(.system(size: 15, design: .monospaced)).foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle("About".translated())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Reusable Sub-components

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.sweeplyTextSub)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func settingsIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color).frame(width: 30, height: 30)
            Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func feedbackBanner(message: String, style: CleanerSettingsFeedbackStyle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: style.iconName).font(.system(size: 14, weight: .semibold)).foregroundStyle(style.accentColor)
            Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyNavy)
            Spacer()
        }
        .padding(14)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(style.accentColor.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Save

    private func saveChanges() async {
        guard let uid = session.userId else {
            feedbackStyle = .error
            feedbackMessage = "No authenticated session was found."
            return
        }
        guard validationMessage == nil else {
            feedbackStyle = .warning
            feedbackMessage = validationMessage
            return
        }
        isSaving = true
        feedbackMessage = nil
        let success = await profileStore.save(localProfile, userId: uid)
        isSaving = false
        if success {
            baselineProfile = localProfile
            feedbackStyle = .success
            feedbackMessage = "Settings saved."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            feedbackStyle = .error
            feedbackMessage = profileStore.lastError ?? "Unable to save your settings right now."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - CleanerSettingsFeedbackStyle

private enum CleanerSettingsFeedbackStyle {
    case info, success, warning, error

    var iconName: String {
        switch self {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .info:    return .sweeplyNavy
        case .success: return .sweeplyAccent
        case .warning: return .sweeplyWarning
        case .error:   return .sweeplyDestructive
        }
    }

    var backgroundColor: Color { accentColor.opacity(0.10) }
}
