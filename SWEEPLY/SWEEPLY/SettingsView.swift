import SwiftUI

enum SettingsTab: String, CaseIterable {
    case profile     = "Profile"
    case business    = "Business"
    case preferences = "Preferences"
    case account     = "Account"

    var icon: String {
        switch self {
        case .profile:     return "person.fill"
        case .business:    return "building.2.fill"
        case .preferences: return "slider.horizontal.3"
        case .account:     return "lock.fill"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self)    private var session
    @Environment(ProfileStore.self)  private var profileStore

    @State private var selectedTab: SettingsTab = .profile
    @State private var appeared = false
    
    // Binding state (will sync with profileStore on save)
    @State private var fullName: String = ""
    @State private var phone: String = ""
    @State private var businessName: String = ""
    @State private var street: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zip: String = ""
    
    @State private var defaultRate: Double = 0
    @State private var defaultDuration: Double = 2.0
    @State private var taxRate: Double = 0
    @State private var paymentTerms: Int = 14
    @State private var services: [BusinessService] = []
    
    // Catalog Add state
    @State private var newServiceName: String = ""
    @State private var newServicePrice: String = ""
    
    // Security
    @State private var newPass: String = ""
    @State private var confirmPass: String = ""
    @State private var showDeleteConfirm = false
    @State private var deleteConfirmText = ""
    @State private var isDeleting = false
    
    @State private var isSaving = false
    @State private var isSavingBusiness = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────
            HStack {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.sweeplyBorder)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // ── Tab Bar ──────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13))
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.sweeplyNavy : Color.clear)
                            .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyTextSub)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)

            // ── Content ──────────────────────────────────────
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case .profile:     profileTab
                    case .business:    businessTab
                    case .preferences: preferencesTab
                    case .account:     accountTab
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .onAppear {
            if let p = profileStore.profile {
                fullName = p.fullName
                phone = p.phone
                businessName = p.businessName
                
                street = p.settings.street
                city = p.settings.city
                state = p.settings.state
                zip = p.settings.zip
                
                defaultRate = p.settings.defaultRate
                defaultDuration = p.settings.defaultDuration
                taxRate = p.settings.taxRate
                paymentTerms = p.settings.paymentTerms
                services = p.settings.services
            }
            withAnimation { appeared = true }
        }
    }

    // MARK: - Tabs

    private var profileTab: some View {
        VStack(spacing: 24) {
            // Card 1: Personal Info
            FormSection(title: "Personal Information", subtitle: "Your name and contact details") {
                VStack(spacing: 16) {
                    SettingsField(label: "Full Name", text: $fullName)
                    SettingsField(label: "Phone", text: $phone)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EMAIL").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                        Text(profileStore.profile?.email ?? "")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .padding(.vertical, 8)
                        Text("Email cannot be changed here")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                }
            }

            // Card 2: Business Info
            FormSection(title: "Business Information", subtitle: "Used on invoices and client-facing documents") {
                VStack(spacing: 16) {
                    SettingsField(label: "Business Name", text: $businessName)
                    SettingsField(label: "Street Address", text: $street)
                    HStack(spacing: 12) {
                        SettingsField(label: "City", text: $city)
                            .frame(maxWidth: .infinity)
                        SettingsField(label: "ST", text: $state)
                            .frame(width: 50)
                        SettingsField(label: "ZIP", text: $zip)
                            .frame(width: 80)
                    }
                }
            }

            // Save Button
            HStack {
                Spacer()
                Button {
                    Task { await saveProfile() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white).padding(.trailing, 4) }
                        Text(isSaving ? "Saving..." : "Save Profile")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSaving)
            }
        }
    }

    private var businessTab: some View {
        VStack(spacing: 24) {
            // Card 1: Service Catalog
            FormSection(title: "Service Catalog", subtitle: "Tap name or price to edit inline") {
                VStack(spacing: 12) {
                    ForEach(services.indices, id: \.self) { idx in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.sweeplyNavy)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            TextField("Name", text: $services[idx].name)
                                .font(.system(size: 14))
                            
                            HStack(spacing: 2) {
                                Text("$").font(.system(size: 13, weight: .semibold))
                                TextField("0.00", value: $services[idx].price, format: .number)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(width: 60)
                            }
                            
                            Button { services.remove(at: idx) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.sweeplyDestructive)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Add Row
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 20, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.sweeplyBorder, style: StrokeStyle(lineWidth: 1, dash: [2])))
                        
                        TextField("Service name...", text: $newServiceName)
                            .font(.system(size: 14))
                        
                        HStack(spacing: 2) {
                            Text("$").font(.system(size: 13))
                            TextField("0", text: $newServicePrice)
                                .font(.system(size: 13))
                                .keyboardType(.decimalPad)
                                .frame(width: 60)
                        }
                        
                        Button { addService() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            // Card 2: Job Defaults
            FormSection(title: "Job Defaults", subtitle: "Applied automatically to new jobs") {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        SettingsField(label: "Default Rate ($)", text: .init(get: { "\(defaultRate)" }, set: { defaultRate = Double($0) ?? 0 }))
                        SettingsField(label: "Duration (Hours)", text: .init(get: { "\(defaultDuration)" }, set: { defaultDuration = Double($0) ?? 2.0 }))
                    }
                    
                    Divider().padding(.vertical, 4).overlay(alignment: .leading) {
                        Text("INVOICE DEFAULTS").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).padding(.horizontal, 8).background(Color.sweeplySurface)
                    }
                    
                    HStack(spacing: 16) {
                        SettingsField(label: "Tax Rate (%)", text: .init(get: { "\(taxRate)" }, set: { taxRate = Double($0) ?? 0 }))
                        SettingsField(label: "Payment Terms (Days)", text: .init(get: { "\(paymentTerms)" }, set: { paymentTerms = Int($0) ?? 14 }))
                    }
                }
            }

            // Save Button
            HStack {
                Spacer()
                Button {
                    Task { await saveBusinessSettings() }
                } label: {
                    HStack {
                        if isSavingBusiness { ProgressView().tint(.white).padding(.trailing, 4) }
                        Text(isSavingBusiness ? "Saving..." : "Save Business Settings")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSavingBusiness)
            }
        }
    }
    
    private var preferencesTab: some View {
        VStack(spacing: 24) {
            SectionCard {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Dark Mode").font(.system(size: 15, weight: .medium))
                            Text("Switch between light and dark theme").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                        }
                        Spacer()
                        Toggle("", isOn: .init(get: { profileStore.profile?.settings.darkMode ?? false }, set: { updateDarkMode($0) }))
                            .labelsHidden()
                            .tint(Color.sweeplyNavy)
                    }
                    .padding(.vertical, 14)

                    Divider()
                    
                    PreferenceComingSoon(title: "Push Notifications", subtitle: "Job reminders and schedule alerts")
                    
                    Divider()
                    
                    PreferenceComingSoon(title: "Email Notifications", subtitle: "Invoice and payment confirmations")
                }
                .padding(-16)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var accountTab: some View {
        VStack(spacing: 24) {
            // Card 1: Change Password
            FormSection(title: "Change Password", subtitle: "Must be at least 6 characters") {
                VStack(spacing: 16) {
                    SecureSettingsField(label: "New Password", text: $newPass)
                    SecureSettingsField(label: "Confirm Password", text: $confirmPass)
                    HStack {
                        Spacer()
                        Button("Update Password") { updatePassword() }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }

            // Card 2: Session
            FormSection(title: "Session", subtitle: "Manage your active session") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                        Text(profileStore.profile?.email ?? "").font(.system(size: 16, weight: .medium))
                    }
                    Spacer()
                    Button {
                        Task { await session.signOut(); dismiss() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.sweeplyDestructive)
                    }
                }
            }

            // Card 3: Danger Zone
            VStack(alignment: .leading, spacing: 8) {
                Text("DANGER ZONE").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyDestructive).tracking(1.2)
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Deletion")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.sweeplyDestructive)
                        Text("Irreversible actions. Proceed with caution.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    
                    Button { showDeleteConfirm = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Delete Account")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.sweeplyDestructive)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyDestructive, lineWidth: 1))
                    }
                }
                .padding(20)
                .background(Color.sweeplyDestructive.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyDestructive.opacity(0.2), lineWidth: 1))
            }
        }
        .fullScreenCover(isPresented: $showDeleteConfirm) {
            DeleteOverlay(confirmText: $deleteConfirmText, isPresented: $showDeleteConfirm)
        }
    }

    // MARK: - Actions

    private func addService() {
        guard !newServiceName.isEmpty, let p = Double(newServicePrice) else { return }
        services.append(BusinessService(name: newServiceName, price: p))
        newServiceName = ""
        newServicePrice = ""
    }

    private func saveBusinessSettings() async {
        guard let current = profileStore.profile else { return }
        isSavingBusiness = true
        var updated = current
        updated.settings.services = services
        updated.settings.defaultRate = defaultRate
        updated.settings.defaultDuration = defaultDuration
        updated.settings.taxRate = taxRate
        updated.settings.paymentTerms = paymentTerms
        
        _ = await profileStore.save(updated, userId: current.id)
        isSavingBusiness = false
    }

    private func updateDarkMode(_ enabled: Bool) {
        guard let current = profileStore.profile else { return }
        var updated = current
        updated.settings.darkMode = enabled
        Task { _ = await profileStore.save(updated, userId: current.id) }
    }

    private func updatePassword() {
        // Implementation for Supabase updatePassword
    }

    private func saveProfile() async {
        guard let current = profileStore.profile else { return }
        isSaving = true
        var updated = current
        updated.fullName = fullName
        updated.phone = phone
        updated.businessName = businessName
        updated.settings.street = street
        updated.settings.city = city
        updated.settings.state = state
        updated.settings.zip = zip
        
        let success = await profileStore.save(updated, userId: current.id)
        isSaving = false
    }
}

// MARK: - Subviews

struct PreferenceComingSoon: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Text("Coming Soon")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
        }
        .padding(.vertical, 14)
        .opacity(0.6)
    }
}

struct SecureSettingsField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
            SecureField("", text: $text)
                .font(.system(size: 16))
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 1)
                }
        }
    }
}

struct DeleteOverlay: View {
    @Binding var confirmText: String
    @Binding var isPresented: Bool
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Delete Account?").font(.system(size: 20, weight: .bold))
                    Text("This is permanent. Please type 'DELETE' to confirm.").font(.system(size: 14)).multilineTextAlignment(.center).foregroundStyle(Color.sweeplyTextSub)
                }
                
                TextField("DELETE", text: $confirmText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                
                HStack(spacing: 12) {
                    Button("Cancel") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(maxWidth: .infinity)
                    
                    Button("Confirm") {
                        // Action
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(confirmText == "DELETE" ? Color.sweeplyDestructive : Color.sweeplyBorder)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(confirmText != "DELETE")
                }
            }
            .padding(24)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(40)
        }
    }
}

// MARK: - Subviews

struct FormSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: () -> Content
    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                content()
            }
        }
    }
}

struct SettingsField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.5)
            TextField("", text: $text)
                .font(.system(size: 16))
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 1)
                }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSession())
        .environment(ProfileStore())
}
