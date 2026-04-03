import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session
    
    @State private var selectedTab: SettingsTab = .profile
    @State private var isSaving = false
    @State private var localProfile: UserProfile = MockData.profile
    @State private var showDeleteConfirmation = false

    private var serviceCatalogBinding: Binding<[BusinessService]> {
        $localProfile.settings.services
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
                        Task { await saveChanges() }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let p = profileStore.profile {
                    localProfile = p
                }
                if localProfile.settings.services.isEmpty {
                    localProfile.settings.services = AppSettings.defaultServiceCatalog
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
                        Text("SERVICE CATALOG").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                        Spacer()
                        Button { addService() } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                    
                    ForEach(serviceCatalogBinding) { $service in
                        HStack(spacing: 12) {
                            TextField("Service Name", text: $service.name)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            TextField("0", value: $service.price, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .frame(width: 60)
                            
                            Button { removeService(service.id) } label: {
                                Image(systemName: "minus.circle").foregroundStyle(Color.sweeplyDestructive)
                            }
                        }
                        .padding(10)
                        .background(Color.sweeplyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        SectionCard {
            VStack(spacing: 20) {
                Toggle(isOn: $localProfile.settings.darkMode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dark Mode").font(.system(size: 15, weight: .semibold))
                        Text("Adaptive editorial appearance").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                .tint(Color.sweeplyNavy)
            }
        }
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
            Button("Permanently Delete", role: .destructive) { /* handle delete */ }
        } message: {
            Text("This action cannot be undone. All your business data will be lost.")
        }
    }
    
    // MARK: - Actions
    
    private func addService() {
        let new = BusinessService(name: "New Service", price: 150)
        localProfile.settings.services.append(new)
    }
    
    private func removeService(_ id: UUID) {
        localProfile.settings.services.removeAll { $0.id == id }
    }
    
    private func resetPassword() {
        // Trigger supabase reset flow
    }
    
    private func saveChanges() async {
        guard let uid = session.userId else { return }
        isSaving = true
        let success = await profileStore.save(localProfile, userId: uid)
        isSaving = false
        if success { dismiss() }
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
