import SwiftUI
import Supabase

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session
    @Environment(NotificationManager.self) private var notificationManager
    
    @State private var selectedTab: SettingsTab = .profile
    @State private var isSaving = false
    @State private var localProfile: UserProfile = MockData.profile
    @State private var baselineProfile: UserProfile = MockData.profile
    @State private var showDeleteConfirmation = false
    @State private var feedbackMessage: String?
    @State private var feedbackStyle: SettingsFeedbackStyle = .info
    @State private var serviceEditorState: ServiceCatalogEditorState?

    private var serviceCatalogBinding: Binding<[BusinessService]> {
        $localProfile.settings.services
    }

    private var hydratedServices: [BusinessService] {
        localProfile.settings.hydratedServiceCatalog
    }

    private var canSave: Bool {
        !isSaving && validationMessage == nil && hasUnsavedChanges
    }

    private var hasUnsavedChanges: Bool {
        profilesMatch(normalizedProfile(localProfile), normalizedProfile(baselineProfile)) == false
    }

    private var validationMessage: String? {
        if localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Full name is required."
        }

        if localProfile.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Business name is required."
        }

        let email = localProfile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || !email.contains("@") {
            return "Enter a valid email address."
        }

        if localProfile.settings.services.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Each service needs a name."
        }

        return nil
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
                // Pill Tab Selector
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(duration: 0.3)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyTextSub)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? Color.sweeplyNavy : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(8)
                .background(Color.sweeplySurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
                .padding(.vertical, 16)
                
                ScrollView {
                    VStack(spacing: 24) {
                        if let feedbackMessage {
                            feedbackBanner(message: feedbackMessage, style: feedbackStyle)
                        } else if let validationMessage {
                            feedbackBanner(message: validationMessage, style: .warning)
                        }

                        switch selectedTab {
                        case .profile:
                            profileSection
                        case .business:
                            businessSection
                        case .preferences:
                            preferencesSection
                        case .account:
                            accountSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await saveChanges() }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                hydrateLocalProfile()
            }
            .sheet(item: $serviceEditorState) { editorState in
                ServiceCatalogEditorSheet(state: editorState) { result in
                    upsertService(from: result)
                }
            }
        }
    }
    
    // MARK: - Sections
    
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionCard {
                VStack(spacing: 16) {
                    SettingsField(label: "Full Name", text: $localProfile.fullName)
                    SettingsField(label: "Email Address", text: $localProfile.email, keyboard: .emailAddress)
                    SettingsField(label: "Phone Number", text: $localProfile.phone, keyboard: .phonePad)
                    SettingsField(label: "Business Name", text: $localProfile.businessName)
                }
            }
        }
    }
    
    private var businessSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Address
            SectionCard {
                VStack(spacing: 16) {
                    Text("BUSINESS ADDRESS").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsField(label: "Street", text: $localProfile.settings.street)
                    HStack(spacing: 12) {
                        SettingsField(label: "City", text: $localProfile.settings.city)
                        SettingsField(label: "State", text: $localProfile.settings.state).frame(width: 70)
                        SettingsField(label: "ZIP", text: $localProfile.settings.zip).frame(width: 90)
                    }
                }
            }
            
            // Service Catalog
            SectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SERVICE CATALOG").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                            Text("This list powers service pickers in new clients and new jobs.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        Spacer()
                        Button { presentNewServiceEditor() } label: {
                            Label("Add Service", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.sweeplyNavy.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }

                    if hydratedServices.isEmpty {
                        Text("Add your first service to start pricing jobs from your business catalog.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(hydratedServices) { service in
                                ServiceCatalogRow(
                                    service: service,
                                    onEdit: { presentEditServiceEditor(service) },
                                    onDelete: { removeService(service.id) }
                                )
                            }
                        }
                    }
                }
            }
            
            // Defaults
            SectionCard {
                VStack(spacing: 16) {
                    Text("DEFAULTS").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Text("Default Hourly Rate").font(.system(size: 14))
                        Spacer()
                        TextField("0", value: $localProfile.settings.defaultRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .frame(width: 80)
                            .padding(8)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    HStack {
                        Text("Default Duration (Hrs)").font(.system(size: 14))
                        Spacer()
                        TextField("2.0", value: $localProfile.settings.defaultDuration, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .frame(width: 80)
                            .padding(8)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    
    private var preferencesSection: some View {
        VStack(spacing: 16) {
            SectionCard {
                VStack(spacing: 20) {
                    Toggle(isOn: Binding(
                        get: { notificationManager.isAuthorized },
                        set: { newValue in
                            if newValue {
                                notificationManager.requestAuthorization()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Push Notifications").font(.system(size: 15, weight: .semibold))
                            Text("Job reminders, invoice alerts, billing updates").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                    .tint(Color.sweeplyNavy)

                    if notificationManager.isAuthorized {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("REMINDER SCHEDULE").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)

                            HStack(spacing: 6) {
                                reminderChip(label: "1 hr before", icon: "clock")
                                reminderChip(label: "Morning of", icon: "sunrise")
                                reminderChip(label: "Day before", icon: "calendar")
                            }
                        }
                    }
                }
            }

            if notificationManager.isAuthorized {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    notificationManager.sendTestNotification()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 14))
                        Text("Send Test Notification")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("5s delay")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .foregroundStyle(Color.sweeplyNavy)
                    .padding(16)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // SECURITY & INTEGRATIONS
            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SECURITY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                        .padding(.bottom, 14)

                    BiometricLockToggleRow()

                    Divider().padding(.vertical, 12)

                    CalendarSyncToggleRow()
                }
            }
        }
    }

    @ViewBuilder
    private func reminderChip(label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.sweeplyNavy)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.sweeplyNavy.opacity(0.08))
        .clipShape(Capsule())
    }
    
    private var accountSection: some View {
        VStack(spacing: 16) {
            SectionCard {
                VStack(spacing: 16) {
                    Button { resetPassword() } label: {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                            Text("Reset Password")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.sweeplyBorder)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
            
            Button { showDeleteConfirmation = true } label: {
                Text("Delete Account")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyDestructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyDestructive.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 24)
        }
        .confirmationDialog("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Permanently Delete", role: .destructive) {
                feedbackStyle = .warning
                feedbackMessage = "Account deletion is not self-serve yet. Contact support before removing your workspace."
            }
        } message: {
            Text("This action cannot be undone. All your business data will be lost.")
        }
    }
    
    // MARK: - Actions
    
    private func presentNewServiceEditor() {
        serviceEditorState = ServiceCatalogEditorState()
    }

    private func presentEditServiceEditor(_ service: BusinessService) {
        serviceEditorState = ServiceCatalogEditorState(service: service)
    }

    private func upsertService(from editorState: ServiceCatalogEditorState) {
        let name = editorState.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = Double(editorState.priceText) ?? 0

        if let serviceID = editorState.serviceID,
           let index = localProfile.settings.services.firstIndex(where: { $0.id == serviceID }) {
            localProfile.settings.services[index].name = name
            localProfile.settings.services[index].price = price
        } else {
            localProfile.settings.services.append(
                BusinessService(name: name, price: price)
            )
        }
        feedbackMessage = nil
    }
    
    private func removeService(_ id: UUID) {
        localProfile.settings.services.removeAll { $0.id == id }
        feedbackMessage = nil
    }
    
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
            feedbackMessage = "Supabase is not configured, so password reset is unavailable."
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
        if let profile = profileStore.profile {
            localProfile = profile
        }

        if localProfile.settings.services.isEmpty {
            localProfile.settings.services = AppSettings.defaultServiceCatalog
        }

        localProfile = normalizedProfile(localProfile)
        baselineProfile = localProfile
    }

    private func normalizedProfile(_ profile: UserProfile) -> UserProfile {
        var normalized = profile
        normalized.fullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.businessName = profile.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.phone = profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.settings.street = profile.settings.street.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.settings.city = profile.settings.city.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.settings.state = profile.settings.state.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.settings.zip = profile.settings.zip.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.settings.services = profile.settings.services.map {
            BusinessService(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), price: $0.price)
        }
        return normalized
    }

    private func profilesMatch(_ lhs: UserProfile, _ rhs: UserProfile) -> Bool {
        lhs.fullName == rhs.fullName &&
        lhs.businessName == rhs.businessName &&
        lhs.email == rhs.email &&
        lhs.phone == rhs.phone &&
        lhs.settings.street == rhs.settings.street &&
        lhs.settings.city == rhs.settings.city &&
        lhs.settings.state == rhs.settings.state &&
        lhs.settings.zip == rhs.settings.zip &&
        lhs.settings.defaultRate == rhs.settings.defaultRate &&
        lhs.settings.defaultDuration == rhs.settings.defaultDuration &&
        lhs.settings.services.count == rhs.settings.services.count &&
        zip(lhs.settings.services, rhs.settings.services).allSatisfy { left, right in
            left.id == right.id &&
            left.name == right.name &&
            left.price == right.price
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
}

private enum SettingsFeedbackStyle {
    case info
    case success
    case warning
    case error

    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .info:
            return .sweeplyNavy
        case .success:
            return .sweeplyAccent
        case .warning:
            return .sweeplyWarning
        case .error:
            return .sweeplyDestructive
        }
    }

    var backgroundColor: Color {
        accentColor.opacity(0.10)
    }
}

struct SettingsField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sweeplyTextSub)
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

/// MARK: - Calendar Sync Toggle

private struct CalendarSyncToggleRow: View {
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled: Bool = false

    var body: some View {
        Toggle(isOn: $calendarSyncEnabled) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync Jobs to iOS Calendar")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("Adds scheduled jobs to your Calendar app")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
        .tint(Color.sweeplyAccent)
        .onChange(of: calendarSyncEnabled) { _, enabled in
            if enabled {
                Task { _ = await CalendarSyncManager.shared.requestAccessIfNeeded() }
            }
        }
    }
}

// MARK: - Biometric Lock Toggle

private struct BiometricLockToggleRow: View {
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled: Bool = false

    var body: some View {
        Toggle(isOn: $biometricLockEnabled) {
            HStack(spacing: 10) {
                Image(systemName: "faceid")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require Face ID to Open")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("Locks app when it goes to background")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
        .tint(Color.sweeplyAccent)
    }
}
