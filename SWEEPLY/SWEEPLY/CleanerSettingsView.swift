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
    @State private var feedbackStyle: SettingsFeedbackStyle = .info
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
                    // ── Avatar header ───────────────────────────────────────
                    avatarHeaderSection
                        .padding(.top, 28)
                        .padding(.bottom, 32)

                    // ── Group 1: Profile ──────────────────────────────────
                    menuGroup {
                        NavigationLink(destination: profilePage) {
                            menuRowLabel(icon: "person.circle", title: "Profile")
                        }
                        .buttonStyle(.plain)
                    }

                    groupDivider()

                    // ── Group 2: Switch / Sign Out ──────────────────────
                    menuGroup {
                        menuRow(icon: "arrow.left.arrow.right", title: "Switch to My Business") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            session.switchToOwnBusiness()
                            dismiss()
                        }
                        rowDivider()
                        menuRow(icon: "rectangle.portrait.and.arrow.right",
                              title: "Sign Out",
                              color: Color.sweeplyDestructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showSignOutAlert = true
                        }
                    }

                    // ── Support / About ────────────────────────────────
                    menuGroup {
                        menuRow(icon: "questionmark.message", title: "Support") { }
                        rowDivider()
                        NavigationLink(destination: aboutPage) {
                            menuRowLabel(icon: "info.circle", title: "About")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
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
                if let p = profileStore.profile {
                    localProfile = p
                    baselineProfile = p
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?".translated())
            }
        }
    }

    // MARK: - Avatar Header

    private var avatarHeaderSection: some View {
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
                if !name.isEmpty {
                    Text(name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Text(membership.businessName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Menu Components

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
            if color != Color.sweeplyDestructive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyBorder)
            }
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

    private var profilePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileAvatarHeader
                    .padding(.top, 28)
                    .padding(.bottom, 32)

                if let msg = validationMessage, hasUnsavedChanges {
                    validationBanner(msg)
                        .padding(.bottom, 16)
                } else if let msg = feedbackMessage {
                    feedbackBanner(msg)
                        .padding(.bottom, 16)
                }

                menuGroup {
                    menuRowLabelEdit(label: "Full Name", value: $localProfile.fullName, icon: "person")
                    rowDivider()
                    menuRowLabelEdit(label: "Email", value: $localProfile.email, icon: "envelope", keyboard: .emailAddress)
                    rowDivider()
                    menuRowLabelEdit(label: "Phone", value: $localProfile.phone, icon: "phone", keyboard: .phonePad)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { localProfile = baselineProfile }
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
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
                if !name.isEmpty {
                    Text(name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                Text(membership.businessName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func menuRowLabelEdit(
        label: String,
        value: Binding<String>,
        icon: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.sweeplyNavy)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
            TextField("", text: value)
                .font(.system(size: 17))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .emailAddress ? .none : .words)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.sweeplySurface)
        .contentShape(Rectangle())
    }

    private var aboutPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.sweeplyAccent)
                    Text("Sweeply")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("Version 1.0.0")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.top, 40)

                Text("The easiest way to run your cleaning business.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Feedback

    private func validationBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func feedbackBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.sweeplyNavy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.sweeplyAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Save

    private func saveChanges() async {
        guard let uid = session.userId else {
            feedbackStyle = .error
            feedbackMessage = "No authenticated session."
            return
        }
        guard validationMessage == nil else {
            feedbackStyle = .error
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
            feedbackMessage = profileStore.lastError ?? "Unable to save settings."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private enum SettingsFeedbackStyle {
    case info, success, error
}