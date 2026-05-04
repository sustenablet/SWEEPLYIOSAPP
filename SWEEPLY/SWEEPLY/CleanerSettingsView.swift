import SwiftUI
import Supabase

struct CleanerSettingsView: View {
    @Environment(\.dismiss)         private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session
    @Environment(NotificationManager.self) private var notificationManager

    let membership: TeamMembership

    @State private var localProfile: UserProfile = MockData.profile
    @State private var baselineProfile: UserProfile = MockData.profile
    @State private var isSaving = false
    @State private var feedbackMessage: String?
    @State private var feedbackStyle: CleanerSettingsFeedbackStyle = .info
    @State private var showSignOutAlert = false
    @State private var currentTestNotificationIndex = 0
    @State private var leaveHoldProgress: CGFloat = 0
    @State private var leaveHoldTask: Task<Void, Never>? = nil
    @State private var isLeavingTeam = false
    @State private var leaveError = false

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
                        rowDivider()
                        NavigationLink(destination: preferencesPage) {
                            menuRowLabel(icon: "slider.horizontal.3", title: "Preferences".translated())
                        }
                        .buttonStyle(.plain)
                    }

                    groupDivider()

                    // ── Group 2: App / Support ─────────────────────────
                    menuGroup {
                        menuRow(icon: "questionmark.message", title: "Support".translated()) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if let url = URL(string: "https://sweeplyapp.online/support") {
                                UIApplication.shared.open(url)
                            }
                        }
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

                    // ── Leave Team ────────────────────────────────────
                    leaveTeamButton

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

    @ViewBuilder
    private var preferencesPage: some View {
        ScrollView {
            preferencesSection
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 48)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle("Preferences".translated())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("NOTIFICATIONS".translated())
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("bell.badge.fill", color: Color(red: 0.95, green: 0.45, blue: 0.2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push Notifications".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                        Text(notificationManager.isAuthorized ? "Enabled — job reminders & alerts".translated() : "Tap to enable job reminders".translated())
                            .font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { notificationManager.isAuthorized },
                        set: { newValue in if newValue { notificationManager.requestAuthorization() } }
                    )).labelsHidden().tint(Color.sweeplyAccent)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)

                if notificationManager.isAuthorized {
                    Divider().padding(.leading, 58)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let types = ["Job Reminder".translated(), "Invoice Due".translated(), "Test".translated()]
                        switch types[currentTestNotificationIndex] {
                        case "Job Reminder".translated():
                            notificationManager.fireInstantBanner(title: "Job in 1 Hour".translated(), body: "Standard Clean at Sarah M. — 123 Main St".translated())
                        case "Invoice Due".translated():
                            notificationManager.fireInstantBanner(title: "Invoice Due Soon".translated(), body: "INV-0042 for Sarah M. is due in 3 days — $320.00".translated())
                        default:
                            notificationManager.sendTestNotification()
                        }
                        currentTestNotificationIndex = (currentTestNotificationIndex + 1) % types.count
                    } label: {
                        HStack(spacing: 14) {
                            settingsIcon("paperplane.fill", color: Color.sweeplyAccent)
                            Text("Test Notification".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                            Spacer()
                            let types = ["Job Reminder".translated(), "Invoice Due".translated(), "Test".translated()]
                            Text(types[currentTestNotificationIndex]).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.sweeplyTextSub)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.sweeplyBorder)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionLabel("LANGUAGE".translated()).padding(.top, 16)
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("globe", color: Color(red: 0.2, green: 0.5, blue: 0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Language".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                        Text("English · Português (Brasil)".translated()).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    LanguagePicker()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

            sectionLabel("SECURITY & SYNC".translated()).padding(.top, 16)
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("faceid", color: Color.sweeplyNavy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face ID Lock".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                        Text("Require Face ID when returning to app".translated()).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    BiometricToggle()
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider().padding(.leading, 58)
                HStack(spacing: 14) {
                    settingsIcon("calendar.badge.plus", color: Color(red: 0.2, green: 0.5, blue: 0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync to Calendar".translated()).font(.system(size: 15)).foregroundStyle(Color.primary)
                        Text("Adds scheduled jobs to your Calendar app".translated()).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    CalendarToggle()
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
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

    // MARK: - Leave Team

    private var leaveTeamButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DANGER ZONE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyDestructive.opacity(0.7))
                .tracking(0.8)
                .padding(.horizontal, 4)

            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.sweeplyDestructive.opacity(0.15))
                        .frame(width: geo.size.width * leaveHoldProgress)
                }

                HStack(spacing: 12) {
                    if isLeavingTeam {
                        ProgressView()
                            .tint(Color.sweeplyDestructive)
                            .scaleEffect(0.85)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "figure.walk.departure")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyDestructive)
                            .frame(width: 20)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isLeavingTeam ? "Leaving team…" : "Leave Team")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyDestructive)
                        if leaveError {
                            Text("Something went wrong — try again.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyDestructive.opacity(0.8))
                        } else {
                            Text(leaveHoldProgress > 0
                                 ? "Keep holding…"
                                 : "Hold to leave this team")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyDestructive.opacity(0.65))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(height: 56)
            .background(Color.sweeplyDestructive.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.sweeplyDestructive.opacity(leaveError ? 0.5 : 0.2), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isLeavingTeam, leaveHoldTask == nil else { return }
                        leaveError = false
                        leaveHoldTask = Task { @MainActor in
                            let holdDuration: TimeInterval = 2.5
                            let start = Date()
                            while !Task.isCancelled {
                                let elapsed = Date().timeIntervalSince(start)
                                let progress = min(elapsed / holdDuration, 1.0)
                                leaveHoldProgress = progress
                                if progress >= 1.0 {
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                    await performLeaveTeam()
                                    return
                                }
                                if Int(elapsed * 4) != Int((elapsed - 0.016) * 4) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                try? await Task.sleep(nanoseconds: 16_000_000)
                            }
                        }
                    }
                    .onEnded { _ in
                        guard !isLeavingTeam else { return }
                        leaveHoldTask?.cancel()
                        leaveHoldTask = nil
                        withAnimation(.easeOut(duration: 0.25)) { leaveHoldProgress = 0 }
                    }
            )
            .disabled(isLeavingTeam)
            .animation(.linear(duration: 0.1), value: leaveHoldProgress)
        }
        .padding(.horizontal, 4)
    }

    @MainActor
    private func performLeaveTeam() async {
        guard let client = SupabaseManager.shared,
              let uid = session.userId else { return }
        leaveHoldTask = nil
        isLeavingTeam = true
        do {
            // Hard-delete the row so the owner's member list is clean
            try await client
                .from("team_members")
                .delete()
                .eq("id", value: membership.id.uuidString)
                .eq("cleaner_user_id", value: uid.uuidString)
                .execute()

            // Notify the owner
            let memberName = profileStore.profile?.fullName.trimmingCharacters(in: .whitespaces) ?? "A team member"
            await NotificationHelper.insert(
                userId: membership.ownerId,
                title: "Team Update",
                message: "\(memberName) left your team and no longer has access to \(membership.businessName).",
                kind: "team"
            )

            session.switchToOwnBusiness()
            dismiss()
        } catch {
            isLeavingTeam = false
            leaveHoldProgress = 0
            withAnimation { leaveError = true }
        }
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

// MARK: - Toggle Wrappers

private struct BiometricToggle: View {
    @AppStorage("biometricLockEnabled") private var enabled: Bool = false
    var body: some View {
        Toggle("", isOn: $enabled).labelsHidden().tint(Color.sweeplyAccent)
    }
}

private struct CalendarToggle: View {
    @AppStorage("calendarSyncEnabled") private var enabled: Bool = false
    var body: some View {
        Toggle("", isOn: $enabled).labelsHidden().tint(Color.sweeplyAccent)
            .onChange(of: enabled) { _, on in
                if on { Task { _ = await CalendarSyncManager.shared.requestAccessIfNeeded() } }
            }
    }
}
