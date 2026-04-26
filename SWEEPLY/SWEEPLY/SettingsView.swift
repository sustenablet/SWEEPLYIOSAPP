import SwiftUI
import Supabase

struct SettingsView: View {
    @Environment(\.dismiss)           private var dismiss
    @Environment(ProfileStore.self)   private var profileStore
    @Environment(AppSession.self)     private var session
    @Environment(NotificationManager.self) private var notificationManager

    @State private var selectedTab: SettingsTab = .profile
    @State private var isSaving = false
    @State private var localProfile: UserProfile = MockData.profile
    @State private var baselineProfile: UserProfile = MockData.profile
    @State private var showDeleteConfirmation = false
    @State private var feedbackMessage: String?
    @State private var feedbackStyle: SettingsFeedbackStyle = .info
    @State private var showServiceCatalog = false
    @State private var showJobExtras = false
    @State private var showOnboarding = false
    @State private var showIntroOnboarding = false
    @State private var currentTestNotificationIndex = 0
    @AppStorage("hasSeenIntroOnboarding") private var hasSeenIntroOnboarding = false

    private var canSave: Bool {
        !isSaving && validationMessage == nil && hasUnsavedChanges
    }

    private var hasUnsavedChanges: Bool {
        profilesMatch(normalizedProfile(localProfile), normalizedProfile(baselineProfile)) == false
    }

    private var validationMessage: String? {
        if localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Full name is required.".translated()
        }
        if localProfile.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Business name is required.".translated()
        }
        let email = localProfile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || !email.contains("@") {
            return "Enter a valid email address.".translated()
        }
        return nil
    }

    private var avatarInitials: String {
        let parts = localProfile.fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "S" : letters.uppercased()
    }

    enum SettingsTab: String, CaseIterable {
        case profile = "Profile"
        case business = "Business"
        case preferences = "Preferences"
        case account = "Account"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector

                ScrollView {
                    VStack(spacing: 24) {
                        if selectedTab == .profile {
                            profileAvatarHeader
                        }

                        if let msg = feedbackMessage {
                            feedbackBanner(message: msg, style: feedbackStyle)
                        } else if let msg = validationMessage {
                            feedbackBanner(message: msg, style: .warning)
                        }

                        switch selectedTab {
                        case .profile:      profileSection
                        case .business:     businessSection
                        case .preferences:  preferencesSection
                        case .account:      accountSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
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
            .onAppear { hydrateLocalProfile() }
            .sheet(isPresented: $showServiceCatalog) {
                ServiceCatalogView()
            }
            .sheet(isPresented: $showJobExtras) {
                ServiceCatalogView(addonsOnly: true)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
                    .environment(profileStore)
                    .environment(session)
            }
            .fullScreenCover(isPresented: $showIntroOnboarding) {
                IntroOnboardingView {
                    hasSeenIntroOnboarding = true
                    showIntroOnboarding = false
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue.translated())
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyTextSub)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(selectedTab == tab ? Color.sweeplyNavy : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.sweeplySurface)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Profile Avatar Header

    private var profileAvatarHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 72, height: 72)
                Text(avatarInitials)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 3) {
                let name = localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                let biz  = localProfile.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    Text(name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                if !biz.isEmpty {
                    Text(biz)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Sections

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

            sectionLabel("BUSINESS").padding(.top, 16)
            SectionCard {
                SettingsField(label: "Business Name", text: $localProfile.businessName)
            }
        }
    }

    private var businessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("BUSINESS ADDRESS".translated())
            SectionCard {
                VStack(spacing: 14) {
                    SettingsAddressField(
                        label: "Street",
                        street: $localProfile.settings.street,
                        city: $localProfile.settings.city,
                        state: $localProfile.settings.state,
                        zip: $localProfile.settings.zip
                    )
                    Divider()
                    HStack(spacing: 12) {
                        SettingsField(label: "City", text: $localProfile.settings.city)
                        SettingsStatePickerField(label: "State", state: $localProfile.settings.state).frame(width: 90)
                        SettingsField(label: "ZIP", text: $localProfile.settings.zip).frame(width: 90)
                    }
                }
            }

            sectionLabel("JOB DEFAULTS".translated()).padding(.top, 16)
            SectionCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Default Hourly Rate".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        TextField("0", value: $localProfile.settings.defaultRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                            .frame(width: 80)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Divider().padding(.vertical, 12)
                    HStack {
                        Text("Default Duration (hrs)".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        TextField("2.0", value: $localProfile.settings.defaultDuration, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                            .frame(width: 80)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            sectionLabel("SERVICE CATALOG".translated()).padding(.top, 16)
            settingsNavRow(
                icon: "list.bullet.clipboard",
                iconBg: Color.sweeplyAccent,
                title: "Manage Services",
                subtitle: catalogServiceCountLabel
            ) { showServiceCatalog = true }
            settingsNavRow(
                icon: "sparkles",
                iconBg: Color.sweeplyWarning,
                title: "Job Extras",
                subtitle: extrasCountLabel
            ) { showJobExtras = true }
        }
    }

    private var catalogServiceCountLabel: String {
        let count = (profileStore.profile ?? MockData.profile).settings.hydratedServiceCatalog
            .filter { !$0.isAddon }.count
        return "\(count) service\(count == 1 ? "" : "s") configured"
    }

    private var extrasCountLabel: String {
        let count = (profileStore.profile ?? MockData.profile).settings.hydratedServiceCatalog
            .filter { $0.isAddon }.count
        return count == 0 ? "No extras yet" : "\(count) extra\(count == 1 ? "" : "s") configured"
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            // MARK: Notifications
            sectionLabel("NOTIFICATIONS")
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("bell.badge.fill", color: Color(red: 0.95, green: 0.45, blue: 0.2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push Notifications".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Text(notificationManager.isAuthorized
                             ? "Enabled — job reminders & alerts"
                             : "Tap to enable job reminders")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { notificationManager.isAuthorized },
                        set: { newValue in if newValue { notificationManager.requestAuthorization() } }
                    ))
                    .labelsHidden()
                    .tint(Color.sweeplyAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if notificationManager.isAuthorized {
                    Divider().padding(.leading, 58)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let notificationTypes = ["Job Reminder", "Invoice Due", "Test"]
                        let type = notificationTypes[currentTestNotificationIndex]
                        
                        switch type {
                        case "Job Reminder":
                            notificationManager.fireInstantBanner(
                                title: "Job in 1 Hour",
                                body: "Standard Clean at Sarah M. — 123 Main St"
                            )
                        case "Invoice Due":
                            notificationManager.fireInstantBanner(
                                title: "Invoice Due Soon",
                                body: "INV-0042 for Sarah M. is due in 3 days — $320.00"
                            )
                        default:
                            notificationManager.sendTestNotification()
                        }
                        
                        currentTestNotificationIndex = (currentTestNotificationIndex + 1) % notificationTypes.count
                    } label: {
                        HStack(spacing: 14) {
                            settingsIcon("paperplane.fill", color: Color.sweeplyAccent)
                            Text("Test Notification".translated())
                                .font(.system(size: 15))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            let notificationTypes = ["Job Reminder", "Invoice Due", "Test"]
                            Text(notificationTypes[currentTestNotificationIndex])
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sweeplyBorder)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: Language
            sectionLabel("LANGUAGE".translated()).padding(.top, 16)
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("globe", color: Color(red: 0.2, green: 0.5, blue: 0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Language".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Text("English · Português (Brasil)".translated())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    LanguagePicker()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // MARK: Security & Sync
            sectionLabel("SECURITY & SYNC".translated()).padding(.top, 16)
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("faceid", color: Color.sweeplyNavy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face ID Lock".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Text("Require Face ID when returning to app".translated())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    BiometricToggle()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 58)

                HStack(spacing: 14) {
                    settingsIcon("calendar.badge.plus", color: Color(red: 0.2, green: 0.5, blue: 0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync to Calendar".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Text("Adds scheduled jobs to your Calendar app".translated())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Spacer()
                    CalendarToggle()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private var systemLanguageLabel: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        if code.hasPrefix("pt") { return "🇧🇷 Português".translated() }
        if code.hasPrefix("es") { return "🇪🇸 Español".translated() }
        return "🇺🇸 English".translated()
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !session.activeMemberships.isEmpty {
                sectionLabel("MY TEAMS".translated())
                settingsGroup {
                    VStack(spacing: 0) {
                        ForEach(Array(session.activeMemberships.enumerated()), id: \.element.id) { idx, membership in
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                session.switchToMembership(membership)
                            } label: {
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
                                    Text("Switch".translated())
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyAccent)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if idx < session.activeMemberships.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }

            sectionLabel("ACCOUNT")
            settingsGroup {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showIntroOnboarding = true
                } label: {
                    HStack(spacing: 14) {
                        settingsIcon("arrow.triangle.2.circlepath", color: Color.sweeplyAccent)
                        Text("Re-run App Intro".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                
                Divider().padding(.leading, 58)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showOnboarding = true
                } label: {
                    HStack(spacing: 14) {
                        settingsIcon("sparkles", color: Color.sweeplyNavy)
                        Text("Re-run Business Setup".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 58)
                
                Button { resetPassword() } label: {
                    HStack(spacing: 14) {
                        settingsIcon("lock.shield.fill", color: Color.sweeplyAccent)
                        Text("Reset Password".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }

            sectionLabel("ABOUT").padding(.top, 16)
            settingsGroup {
                HStack(spacing: 14) {
                    settingsIcon("info.circle.fill", color: Color(red: 0.5, green: 0.5, blue: 0.55))
                    Text("Version".translated())
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 58)

                HStack(spacing: 14) {
                    settingsIcon("hammer.fill", color: Color(red: 0.5, green: 0.5, blue: 0.55))
                    Text("Build".translated())
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Button { showDeleteConfirmation = true } label: {
                HStack(spacing: 14) {
                    settingsIcon("trash.fill", color: Color.sweeplyDestructive)
                    Text("Delete Account".translated())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyDestructive)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.sweeplyDestructive.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.sweeplyDestructive.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .confirmationDialog("Delete Account?".translated(), isPresented: $showDeleteConfirmation) {
            Button("Permanently Delete", role: .destructive) {
                feedbackStyle = .warning
                feedbackMessage = "Account deletion is not self-serve yet. Contact support before removing your workspace."
            }
        } message: {
            Text("This action cannot be undone. All your business data will be lost.".translated())
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
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func settingsNavRow(
        icon: String, iconBg: Color,
        title: String, subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                settingsIcon(icon, color: iconBg)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyBorder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingsIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 30, height: 30)
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func feedbackBanner(message: String, style: SettingsFeedbackStyle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: style.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style.accentColor)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
        }
        .padding(14)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func resetPassword() {
        let email = localProfile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            feedbackStyle = .warning
            feedbackMessage = "Add your email address before requesting a password reset."
            selectedTab = .profile
            return
        }
        guard let client = SupabaseManager.shared else {
            feedbackStyle = .warning
            feedbackMessage = "Password reset is not available in this mode."
            return
        }
        Task {
            do {
                try await client.auth.resetPasswordForEmail(email)
                feedbackStyle = .success
                feedbackMessage = "Password reset email sent to \(email)."
            } catch {
                feedbackStyle = .error
                feedbackMessage = error.localizedDescription
            }
        }
    }

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
            baselineProfile = normalizedProfile(localProfile)
            feedbackStyle = .success
            feedbackMessage = "Settings saved."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            feedbackStyle = .error
            feedbackMessage = profileStore.lastError ?? "Unable to save your settings right now."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func hydrateLocalProfile() {
        if let profile = profileStore.profile { localProfile = profile }
        if localProfile.settings.services.isEmpty {
            localProfile.settings.services = AppSettings.defaultServiceCatalog
        }
        localProfile = normalizedProfile(localProfile)
        baselineProfile = localProfile
    }

    private func normalizedProfile(_ profile: UserProfile) -> UserProfile {
        var n = profile
        n.fullName     = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        n.businessName = profile.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        n.email        = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        n.phone        = profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        n.settings.street  = profile.settings.street.trimmingCharacters(in: .whitespacesAndNewlines)
        n.settings.city    = profile.settings.city.trimmingCharacters(in: .whitespacesAndNewlines)
        n.settings.state   = profile.settings.state.trimmingCharacters(in: .whitespacesAndNewlines)
        n.settings.zip     = profile.settings.zip.trimmingCharacters(in: .whitespacesAndNewlines)
        n.settings.services = profile.settings.services.map {
            BusinessService(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), price: $0.price)
        }
        return n
    }

    private func profilesMatch(_ lhs: UserProfile, _ rhs: UserProfile) -> Bool {
        lhs.fullName      == rhs.fullName      &&
        lhs.businessName  == rhs.businessName  &&
        lhs.email         == rhs.email         &&
        lhs.phone         == rhs.phone         &&
        lhs.settings.street   == rhs.settings.street   &&
        lhs.settings.city     == rhs.settings.city     &&
        lhs.settings.state    == rhs.settings.state    &&
        lhs.settings.zip      == rhs.settings.zip      &&
        lhs.settings.defaultRate     == rhs.settings.defaultRate     &&
        lhs.settings.defaultDuration == rhs.settings.defaultDuration &&
        lhs.settings.services.count  == rhs.settings.services.count  &&
        zip(lhs.settings.services, rhs.settings.services).allSatisfy {
            $0.id == $1.id && $0.name == $1.name && $0.price == $1.price
        }
    }
}

// MARK: - SettingsFeedbackStyle

private enum SettingsFeedbackStyle {
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

// MARK: - SettingsField

struct SettingsField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            TextField("", text: $text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }
}

// MARK: - Thin Toggle Wrappers (used inside settingsGroup rows)

private struct BiometricToggle: View {
    @AppStorage("biometricLockEnabled") private var enabled: Bool = false
    var body: some View {
        Toggle("", isOn: $enabled).labelsHidden().tint(Color.sweeplyAccent)
    }
}

private struct CalendarToggle: View {
    @AppStorage("calendarSyncEnabled") private var enabled: Bool = false
    var body: some View {
        Toggle("", isOn: $enabled)
            .labelsHidden()
            .tint(Color.sweeplyAccent)
            .onChange(of: enabled) { _, on in
                if on { Task { _ = await CalendarSyncManager.shared.requestAccessIfNeeded() } }
            }
    }
}
