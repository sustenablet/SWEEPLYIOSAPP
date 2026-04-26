import SwiftUI

struct CleanerSettingsView: View {
    @Environment(\.dismiss)         private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session

    let membership: TeamMembership

    @State private var selectedTab: Tab = .profile
    @State private var localProfile: UserProfile = MockData.profile
    @State private var baselineProfile: UserProfile = MockData.profile
    @State private var isSaving = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var showSignOutAlert = false

    enum Tab: String, CaseIterable {
        case profile = "Profile"
        case account = "Account"
    }

    private var hasUnsavedChanges: Bool { localProfile.fullName != baselineProfile.fullName || localProfile.email != baselineProfile.email || localProfile.phone != baselineProfile.phone }

    private var validationMessage: String? {
        if localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Full name is required.".translated() }
        let email = localProfile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || !email.contains("@") { return "Enter a valid email address.".translated() }
        return nil
    }

    private var canSave: Bool { !isSaving && validationMessage == nil && hasUnsavedChanges }

    private var avatarInitials: String {
        let parts = localProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector

                ScrollView {
                    VStack(spacing: 24) {
                        if selectedTab == .profile { profileAvatarHeader }

                        if let msg = feedbackMessage {
                            feedbackBanner(msg)
                        } else if let msg = validationMessage, hasUnsavedChanges {
                            feedbackBanner(msg)
                        }

                        switch selectedTab {
                        case .profile: profileSection
                        case .account: accountSection
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
            .onAppear {
                if let p = profileStore.profile { localProfile = p; baselineProfile = p }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?".translated())
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue)
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
                Text(localProfile.fullName.isEmpty ? "Team Member" : localProfile.fullName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(membership.businessName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Profile Section

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

            sectionLabel("TEAM").padding(.top, 16)
            SectionCard {
                HStack {
                    Text("Working with".translated())
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Spacer()
                    Text(membership.businessName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(14)
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                session.switchToOwnBusiness()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Switch to My Business".translated())
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.sweeplyNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sweeplyAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1))
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSignOutAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sign Out".translated())
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.sweeplyTextSub)
            .tracking(0.5)
    }

    private func feedbackBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(feedbackIsError ? Color.red : Color.sweeplyTextSub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((feedbackIsError ? Color.red : Color.sweeplyAccent).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func saveChanges() async {
        guard let uid = session.userId else {
            feedbackIsError = true; feedbackMessage = "No authenticated session."; return
        }
        guard validationMessage == nil else {
            feedbackIsError = true; feedbackMessage = validationMessage; return
        }
        isSaving = true; feedbackMessage = nil
        let success = await profileStore.save(localProfile, userId: uid)
        isSaving = false
        if success {
            baselineProfile = localProfile
            feedbackIsError = false; feedbackMessage = "Settings saved."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            feedbackIsError = true
            feedbackMessage = profileStore.lastError ?? "Unable to save settings."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
